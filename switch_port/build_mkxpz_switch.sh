#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════════
# 🎮 Nintendo Switch Build Script for mkxp-z
# ══════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo "  Building mkxp-z for Nintendo Switch (Homebrew)"
echo "════════════════════════════════════════════════════════════"

# ──────────────────────────────────────────────────────────────
# Setup devkitPro toolchain environment
# ──────────────────────────────────────────────────────────────
export DEVKITPRO=/opt/devkitpro
export DEVKITARM=${DEVKITPRO}/devkitA64
export PATH=${DEVKITARM}/bin:${DEVKITPRO}/tools/bin:$PATH

export ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${ROOT}/build-switch
LIBS=${ROOT}/libs
CROSS_FILE=${ROOT}/switch_port/switch.ini

# ──────────────────────────────────────────────────────────────
# CRITICAL: Force pkg-config to ONLY use Switch libraries
# This prevents contamination from system x86_64 libraries
# ──────────────────────────────────────────────────────────────
export PKG_CONFIG_LIBDIR=/opt/devkitpro/portlibs/switch/lib/pkgconfig:/opt/devkitpro/libnx/lib/pkgconfig
export PKG_CONFIG_PATH=
export PKG_CONFIG_SYSROOT_DIR=/opt/devkitpro

echo ""
echo "📋 Build Configuration:"
echo "  • Source:      ${ROOT}"
echo "  • Build Dir:   ${BUILD}"
echo "  • Cross File:  ${CROSS_FILE}"
echo "  • Toolchain:   ${DEVKITARM}"
echo ""

# ──────────────────────────────────────────────────────────────
# Verify custom libraries exist
# ──────────────────────────────────────────────────────────────
echo "🔍 Verifying custom libraries..."

REQUIRED_LIBS=(
    "${LIBS}/ruby-switch/lib/libruby-static.a"
    "${LIBS}/physfs-switch/lib/libphysfs.a"
    "${LIBS}/SDL_sound-switch/lib/libSDL2_sound.a"
)

for lib in "${REQUIRED_LIBS[@]}"; do
    if [ ! -f "$lib" ]; then
        echo "❌ ERROR: Required library not found: $lib"
        echo "   Please run dependency build scripts first!"
        exit 1
    fi
    echo "  ✓ Found: $(basename $lib)"
done

echo ""

# ──────────────────────────────────────────────────────────────
# Clean previous build
# ──────────────────────────────────────────────────────────────
if [ -d "${BUILD}" ]; then
    echo "🧹 Cleaning previous build directory..."
    rm -rf "${BUILD}" 2>/dev/null || echo "  ⚠️  Some files couldn't be removed (may need sudo), continuing..."
fi
if [ -d "${ROOT}/switch" ]; then
    rm -rf "${ROOT}/switch" 2>/dev/null || echo "  ⚠️  Some switch files couldn't be removed, continuing..."
fi

# ──────────────────────────────────────────────────────────────
# Patch mkxp-z source for Switch compatibility
# ──────────────────────────────────────────────────────────────
echo "🔧 Patching mkxp-z source for Switch compatibility..."

# Fix strdup in eventthread.cpp
if ! grep -q "switch_compat.h" "${ROOT}/src/eventthread.cpp"; then
    cat > "${ROOT}/src/switch_compat.h" << 'EOF'
#ifndef SWITCH_COMPAT_H
#define SWITCH_COMPAT_H
#ifdef __SWITCH__
#include <cstring>
#include <cstdlib>
#ifndef strdup
inline char* strdup(const char* s) {
    size_t len = strlen(s) + 1;
    char* copy = (char*)malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}
#endif
#endif
#endif
EOF
    sed -i '1i#include "switch_compat.h"' "${ROOT}/src/eventthread.cpp"
    echo "  ✓ Patched eventthread.cpp for strdup"
fi


# Create universal assert compatibility header for Switch
cat > "${ROOT}/src/switch_assert_compat.h" << 'EOF'
#ifndef SWITCH_ASSERT_COMPAT_H
#define SWITCH_ASSERT_COMPAT_H

#ifdef __SWITCH__
#ifdef __cplusplus
// C++ files
#include <cassert>
#ifndef assert
#include <assert.h>
extern "C" void __assert_func(const char *, int, const char *, const char *) __attribute__((__noreturn__));
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))
#endif
#else
// C files
#include <assert.h>
#ifndef assert
extern void __assert_func(const char *, int, const char *, const char *) __attribute__((__noreturn__));
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))
#endif
#endif
#endif

#endif
EOF

# Add to problematic files
for file in src/audio/al-util.h src/audio/audiostream.cpp src/audio/midisource.cpp src/audio/sharedmidistate.h; do
    if [ -f "${ROOT}/$file" ] && ! grep -q "switch_assert_compat.h" "${ROOT}/$file"; then
        sed -i '1i#include "switch_assert_compat.h"' "${ROOT}/$file"
    fi
done

echo "  ✓ Added Switch assert compatibility header"

# ──────────────────────────────────────────────────────────────
# Fix assert macro issues for additional problematic files
# ──────────────────────────────────────────────────────────────
echo "🔧 Fixing assert macro issues in additional files..."

# Fix config.cpp
if ! grep -q "<cassert>" "${ROOT}/src/config.cpp"; then
    sed -i '/#include "system\/system.h"/a #include <cassert>' "${ROOT}/src/config.cpp"
    echo "  ✓ Fixed assert in config.cpp"
fi

# Fix keybindings.h - needs special handling
if [ -f "${ROOT}/src/input/keybindings.h" ]; then
    # Replace assert.h with cassert
    sed -i 's/#include <assert\.h>/#include <cassert>/' "${ROOT}/src/input/keybindings.h" 2>/dev/null || true
    # If no assert include exists, add cassert after input.h
    if ! grep -q "cassert" "${ROOT}/src/input/keybindings.h"; then
        sed -i '/#include "input.h"/a #include <cassert>' "${ROOT}/src/input/keybindings.h"
    fi
    echo "  ✓ Fixed assert in keybindings.h"
fi

# Fix global-ibo.h
if [ -f "${ROOT}/src/display/gl/global-ibo.h" ] && ! grep -q "<cassert>" "${ROOT}/src/display/gl/global-ibo.h"; then
    # Add after the header guard
    sed -i '/#define GLOBAL_IBO_H/a \n#include <cassert>' "${ROOT}/src/display/gl/global-ibo.h"
    echo "  ✓ Fixed assert in global-ibo.h"
fi

# Fix glstate.h
if [ -f "${ROOT}/src/display/gl/glstate.h" ]; then
    # Replace assert.h with cassert
    sed -i 's/#include <assert\.h>/#include <cassert>/' "${ROOT}/src/display/gl/glstate.h"
    echo "  ✓ Fixed assert in glstate.h"
fi

# Fix bitmap.cpp
if [ -f "${ROOT}/src/display/bitmap.cpp" ] && ! grep -q "<cassert>" "${ROOT}/src/display/bitmap.cpp"; then
    # Add after the last include before the closing brace
    sed -i '/^#include "libnsgif\/libnsgif.h"/a #include <cassert>' "${ROOT}/src/display/bitmap.cpp"
    echo "  ✓ Fixed assert in bitmap.cpp"
fi

# Fix sharedstate.cpp by ensuring cassert is included early
if [ -f "${ROOT}/src/sharedstate.cpp" ] && ! grep -q "<cassert>" "${ROOT}/src/sharedstate.cpp"; then
    sed -i '1i#include <cassert>' "${ROOT}/src/sharedstate.cpp"
    echo "  ✓ Fixed assert in sharedstate.cpp"
fi

# Fix eventthread.cpp assert issues
if [ -f "${ROOT}/src/eventthread.cpp" ] && ! grep -q "<cassert>" "${ROOT}/src/eventthread.cpp"; then
    sed -i '/#include "switch_compat.h"/a #include <cassert>' "${ROOT}/src/eventthread.cpp"
    echo "  ✓ Fixed assert in eventthread.cpp"
fi

echo ""

# For Switch, we need to ensure assert macro is properly defined
# Create a switch-specific assert wrapper
cat > "${ROOT}/src/theoraplay/switch_assert.h" << 'EOF'
#ifndef SWITCH_ASSERT_H
#define SWITCH_ASSERT_H

#ifdef __SWITCH__
#include <assert.h>
// If assert isn't defined as a macro, define it
#ifndef assert
#ifdef NDEBUG
#define assert(x) ((void)0)
#else
extern void __assert_func(const char *, int, const char *, const char *);
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))
#endif
#endif
#endif

#endif
EOF

# Add include to theoraplay.c if not already there
if ! grep -q "switch_assert.h" "${ROOT}/src/theoraplay/theoraplay.c"; then
    sed -i '17a#include "switch_assert.h"' "${ROOT}/src/theoraplay/theoraplay.c"
    echo "  ✓ Added Switch assert wrapper"
fi

echo ""

# ──────────────────────────────────────────────────────────────
# Patch httplib.h for Switch (wrap unavailable POSIX headers)
# ──────────────────────────────────────────────────────────────
HTTPLIB="${ROOT}/src/net/httplib.h"

if ! grep -q "__SWITCH__.*sys/un.h" "${HTTPLIB}"; then
    echo "🔧 Patching httplib.h for Switch compatibility..."
    
    # Create backup
    cp "${HTTPLIB}" "${HTTPLIB}.bak"
    
    # Apply patches with awk
    awk '
    /^#include <sys\/un\.h>/ {
        print "#ifndef __SWITCH__"
        print $0
        print "#endif"
        next
    }
    
    /^#include <sys\/mman\.h>/ {
        print "#ifndef __SWITCH__"
        print $0
        print "#endif"
        next
    }
    
    /^#include <ifaddrs\.h>/ {
        print "#ifndef __SWITCH__"
        print $0
        print "#endif"
        next
    }
    
    { print }
    ' "${HTTPLIB}.bak" > "${HTTPLIB}"
    
    rm "${HTTPLIB}.bak"
    echo "  ✓ Wrapped sys/un.h, sys/mman.h, ifaddrs.h"
else
    echo "  ℹ httplib.h already patched for Switch"
fi

echo ""

# ──────────────────────────────────────────────────────────────
# Patch ghc/filesystem.hpp for Switch support
# ──────────────────────────────────────────────────────────────

# First, remove any old patches
rm -f "${ROOT}/src/filesystem/switch_filesystem_shim.h"

if ! grep -q "GHC_OS_SWITCH" "${ROOT}/src/filesystem/ghc/filesystem.hpp"; then
    echo "🔧 Patching ghc/filesystem.hpp for Switch..."
    
    # Directly edit line 72 (before the #else at line 73) to add Switch detection
    # Use ex (line editor) for precise line insertion
    ex "${ROOT}/src/filesystem/ghc/filesystem.hpp" <<'EXEOF'
72a
#elif defined(__SWITCH__)
#define GHC_OS_SWITCH
#define GHC_OS_LINUX
.
wq
EXEOF
    
    echo "  ✓ Added Switch OS detection"
fi

# Also stub out missing POSIX functions for Switch
# Check if the FILE exists, not if the include line exists
if [ ! -f "${ROOT}/src/filesystem/switch_filesystem_shim.h" ]; then
    echo "🔧 Adding Switch filesystem shims..."
    
    cat > "${ROOT}/src/filesystem/switch_filesystem_shim.h" << 'EOF'
#ifndef SWITCH_FILESYSTEM_SHIM_H
#define SWITCH_FILESYSTEM_SHIM_H

#ifdef __SWITCH__
#include <sys/stat.h>
#include <errno.h>

/* AT_* constants */
#ifndef AT_FDCWD
#define AT_FDCWD (-100)
#endif
#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x100
#endif

/* Stub unsupported POSIX functions */
static inline int symlink(const char *target, const char *linkpath) {
    (void)target; (void)linkpath;
    errno = ENOSYS;
    return -1;
}

static inline ssize_t readlink(const char *pathname, char *buf, size_t bufsiz) {
    (void)pathname; (void)buf; (void)bufsiz;
    errno = EINVAL;
    return -1;
}

static inline int utimensat(int dirfd, const char *pathname, 
                            const struct timespec times[2], int flags) {
    (void)dirfd; (void)pathname; (void)times; (void)flags;
    return 0;
}

static inline int truncate(const char *path, off_t length) {
    (void)path; (void)length;
    errno = ENOSYS;
    return -1;
}

#endif /* __SWITCH__ */
#endif /* SWITCH_FILESYSTEM_SHIM_H */
EOF

    echo "  ✓ Created Switch filesystem shim header"
fi

# Ensure the include line is there
if ! grep -q "switch_filesystem_shim" "${ROOT}/src/filesystem/filesystemImpl.cpp"; then
    sed -i '1i#include "switch_filesystem_shim.h"' "${ROOT}/src/filesystem/filesystemImpl.cpp"
    echo "  ✓ Added Switch filesystem shims"
fi

echo ""

# ──────────────────────────────────────────────────────────────
# Patch ghc/filesystem.hpp strerror_r (direct sed approach)
# ──────────────────────────────────────────────────────────────
if ! grep -q "ifdef __SWITCH__" "${ROOT}/src/filesystem/ghc/filesystem.hpp" | grep -q "strerror"; then
    echo "🔧 Patching strerror_r in ghc/filesystem.hpp..."
    
    # Find the line with strerror_r and add Switch wrapper
    sed -i '/return strerror_adapter(strerror_r/i #ifdef __SWITCH__\n    return std::string(strerror(code ? code : errno));\n#else' "${ROOT}/src/filesystem/ghc/filesystem.hpp"
    sed -i '/return strerror_adapter(strerror_r/a #endif' "${ROOT}/src/filesystem/ghc/filesystem.hpp"
    
    echo "  ✓ Patched strerror_r for Switch"
fi

echo ""

# ──────────────────────────────────────────────────────────────
# Patch net.cpp to stub out networking on Switch
# ──────────────────────────────────────────────────────────────
NET_CPP="${ROOT}/src/net/net.cpp"

if ! grep -q "__SWITCH__.*networking stub" "${NET_CPP}"; then
    echo "🔧 Stubbing out networking module for Switch..."
    
    # Create backup
    cp "${NET_CPP}" "${NET_CPP}.bak"
    
    # Write the full stub
    cat > "${NET_CPP}" << 'NETEOF'
#ifdef __SWITCH__
// Switch: networking disabled — not needed for local gameplay
#include <string>

namespace mkxp
{

// Define a minimal stub class so the linker sees the proper symbols.
// The real class is not available on Switch builds.
struct Net
{
    static bool isAvailable();
    static void downloadToFile(const std::string &url, const std::string &path);
    static std::string downloadToMemory(const std::string &url);
    static int  getProgress();
    static bool isDownloading();
    static void cancelDownload();
};

// Stub implementations
bool Net::isAvailable()              { return false; }
void Net::downloadToFile(const std::string &, const std::string &) { }
std::string Net::downloadToMemory(const std::string &)             { return ""; }
int Net::getProgress()               { return 0; }
bool Net::isDownloading()            { return false; }
void Net::cancelDownload()           { }

} // namespace mkxp

#else
// ──────────────────────────────────────────────
// Non‑Switch: compile the original implementation
// ──────────────────────────────────────────────
#include "net.h"
#include <string>
NETEOF

    # Append the original unmodified implementation
    cat "${NET_CPP}.bak" >> "${NET_CPP}"
    
    # Close conditional
    echo -e "\n#endif // __SWITCH__ networking stub" >> "${NET_CPP}"
    
    rm "${NET_CPP}.bak"
    echo "  ✓ Networking stub patched for Switch."
else
    echo "  ℹ net.cpp already patched for Switch"
fi

echo ""

# ──────────────────────────────────────────────────────────────
# Create minimal Switch platform files
# ──────────────────────────────────────────────────────────────
echo "🔧 Creating Switch platform stubs..."

# ALWAYS delete and recreate - no conditions
rm -rf "${ROOT}/switch"
mkdir -p "${ROOT}/switch"

# Create stub files FIRST (before platform files)
cat > "${ROOT}/switch/switch_iconv_stub.c" << 'ICONVEOF'
#ifdef __SWITCH__
#include <stdlib.h>
#include <string.h>

typedef void* iconv_t;

iconv_t libiconv_open(const char* tocode, const char* fromcode) {
    (void)tocode; (void)fromcode;
    return (iconv_t)1; // Return non-null to indicate "success"
}

size_t libiconv(iconv_t cd, char** inbuf, size_t* inbytesleft, 
                char** outbuf, size_t* outbytesleft) {
    (void)cd;
    // Simple pass-through: copy input to output
    if (inbuf && *inbuf && outbuf && *outbuf && inbytesleft && outbytesleft) {
        size_t to_copy = (*inbytesleft < *outbytesleft) ? *inbytesleft : *outbytesleft;
        memcpy(*outbuf, *inbuf, to_copy);
        *inbuf += to_copy;
        *outbuf += to_copy;
        *inbytesleft -= to_copy;
        *outbytesleft -= to_copy;
    }
    return 0; // Success
}

int libiconv_close(iconv_t cd) {
    (void)cd;
    return 0; // Success
}
#endif
ICONVEOF

cat > "${ROOT}/switch/switch_getrusage_stub.c" << 'GETRUSAGEEOF'
#ifdef __SWITCH__
#include <sys/time.h>
#include <sys/resource.h>
#include <string.h>

int getrusage(int who, struct rusage *usage) {
    (void)who;
    if (usage) {
        memset(usage, 0, sizeof(struct rusage));
    }
    return 0; // Success
}
#endif
GETRUSAGEEOF

cat > "${ROOT}/switch/switch_http_stub.cpp" << 'HTTPEOF'
#ifdef __SWITCH__
#include "net/net.h"

namespace mkxp_net {

// HTTPResponse implementation
int HTTPResponse::status() { return 0; }
std::string &HTTPResponse::body() { return _body; }
StringMap &HTTPResponse::headers() { return _headers; }
HTTPResponse::~HTTPResponse() {}
HTTPResponse::HTTPResponse() : _status(0) {}

// HTTPRequest implementation
HTTPRequest::HTTPRequest(const char *dest, bool follow_redirects) {
    (void)dest; (void)follow_redirects;
}
HTTPRequest::~HTTPRequest() {}

StringMap &HTTPRequest::headers() { return _headers; }

HTTPResponse HTTPRequest::get() {
    return HTTPResponse();
}

HTTPResponse HTTPRequest::post(StringMap &postData) {
    (void)postData;
    return HTTPResponse();
}

HTTPResponse HTTPRequest::post(const char *body, const char *content_type) {
    (void)body; (void)content_type;
    return HTTPResponse();
}

} // namespace mkxp_net
#endif
HTTPEOF

cat > "${ROOT}/switch/switch_posix_stubs.c" << 'POSIXEOF'
#ifdef __SWITCH__
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <signal.h>
#include <errno.h>

// pthread_kill stub
int pthread_kill(pthread_t thread, int sig) {
    (void)thread; (void)sig;
    return 0; // Success
}

// sysconf stub
long sysconf(int name) {
    (void)name;
    return 0; // Return 0 for most things
}

// getuid stub
uid_t getuid(void) {
    return 0; // Root/Single user
}

// getpwuid stub
struct passwd *getpwuid(uid_t uid) {
    (void)uid;
    return NULL; // No password entry
}

// pipe stub
int pipe(int pipefd[2]) {
    (void)pipefd;
    errno = ENOSYS;
    return -1;
}

// geteuid stub
uid_t geteuid(void) {
    return 0;
}

// getgid stub
gid_t getgid(void) {
    return 0;
}

// getegid stub
gid_t getegid(void) {
    return 0;
}

// waitpid stub
pid_t waitpid(pid_t pid, int *status, int options) {
    (void)pid; (void)status; (void)options;
    errno = ECHILD;
    return -1;
}

// umask stub
mode_t umask(mode_t mask) {
    (void)mask;
    return 0;
}

// execv stub
int execv(const char *path, char *const argv[]) {
    (void)path; (void)argv;
    errno = ENOSYS;
    return -1;
}

// getppid stub
pid_t getppid(void) {
    return 0;
}

// getpwnam stub
struct passwd *getpwnam(const char *name) {
    (void)name;
    return NULL;
}

// endpwent stub
void endpwent(void) {
}

// execl stub
int execl(const char *path, const char *arg, ...) {
    (void)path; (void)arg;
    errno = ENOSYS;
    return -1;
}

// execle stub
int execle(const char *path, const char *arg, ...) {
    (void)path; (void)arg;
    errno = ENOSYS;
    return -1;
}

// rb_mjit_fork stub (Ruby MJIT)
pid_t rb_mjit_fork(void) {
    errno = ENOSYS;
    return -1;
}

// chown stub
int chown(const char *pathname, uid_t owner, gid_t group) {
    (void)pathname; (void)owner; (void)group;
    return 0;
}

// popen stub
FILE *popen(const char *command, const char *type) {
    (void)command; (void)type;
    return NULL;
}

// pclose stub
int pclose(FILE *stream) {
    (void)stream;
    return -1;
}
#endif
POSIXEOF

# Now create platform files
cat > "${ROOT}/switch/switch_main.cpp" << 'SWITCHEOF'
#ifdef __SWITCH__
#include <switch.h>
#include <stdio.h>
#include <unistd.h>

extern "C" {
    void userAppInit(void);
    void userAppExit(void);
}

void userAppInit(void) { romfsInit(); socketInitializeDefault(); }
void userAppExit(void) { socketExit(); romfsExit(); }
#endif
SWITCHEOF

cat > "${ROOT}/switch/SwitchFilesystem.cpp" << 'SWITCHEOF'
#ifdef __SWITCH__
// Stub - default filesystem works
#endif
SWITCHEOF

cat > "${ROOT}/switch/SwitchInput.cpp" << 'SWITCHEOF'
#ifdef __SWITCH__
// Stub - SDL2 handles input
#endif
SWITCHEOF

# Create meson.build for the switch directory
cat > "${ROOT}/switch/meson.build" << 'MESONEOF'
# Switch platform stub implementations
switch_stub_sources = files(
  'switch_iconv_stub.c',
  'switch_getrusage_stub.c',
  'switch_http_stub.cpp',
  'switch_posix_stubs.c'
)

# Build as a static library
switch_stubs = static_library('switch_stubs',
  switch_stub_sources,
  include_directories: include_directories('../src')
)
MESONEOF

echo "  ✓ Created Switch platform stubs (including meson.build)"

echo ""

# ──────────────────────────────────────────────────────────────
# Configure with Meson
# ──────────────────────────────────────────────────────────────
echo "🔧 Configuring mkxp-z for Nintendo Switch with Meson..."
echo ""

meson setup "${BUILD}" "${ROOT}" \
    --cross-file "${CROSS_FILE}" \
    -Ddefault_library=static \
    -Dbuildtype=release \
    -Dshared_fluid=false \
    -Duse_miniffi=false

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Meson configuration failed!"
    echo "   Check the error messages above for details."
    exit 1
fi

echo ""
echo "✅ Configuration successful!"
echo ""

# ──────────────────────────────────────────────────────────────
# Build with Ninja
# ──────────────────────────────────────────────────────────────
echo "🔨 Building mkxp-z (this may take several minutes)..."
echo ""

ninja -C "${BUILD}" -v

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Build failed!"
    echo "   Check compiler errors above."
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  🎉 Build Successful!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Output ELF: ${BUILD}/mkxp-z"
echo ""

# Generate NRO if elf2nro is available
if command -v elf2nro >/dev/null 2>&1; then
    echo "📦 Generating .nro file..."
    elf2nro "${BUILD}/mkxp-z" "${BUILD}/mkxp-z.nro" --icon="${ROOT}/assets/icon.png" --nacp="${ROOT}/assets/mkxp-z.nacp" 2>/dev/null || \
    elf2nro "${BUILD}/mkxp-z" "${BUILD}/mkxp-z.nro"
    
    if [ -f "${BUILD}/mkxp-z.nro" ]; then
        echo "  ✅ Generated: ${BUILD}/mkxp-z.nro"
    else
        echo "  ⚠️  Failed to generate .nro file"
    fi
else
    echo "⚠️  elf2nro not found, skipping .nro generation"
fi

echo ""
echo "Next steps:"
echo "  1. Copy to SD card:  /switch/mkxp-z/"
echo "  2. Add game assets:  /switch/mkxp-z/Game.rgssad"
echo ""
echo "════════════════════════════════════════════════════════════"