#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════════
# Build Ruby 3.2.2 for Nintendo Switch
# ══════════════════════════════════════════════════════════════

echo "════════════════════════════════════════════════════════════"
echo "  Building Ruby 3.2.2 for Nintendo Switch"
echo "════════════════════════════════════════════════════════════"

# 1. Setup Paths
export DEVKITPRO=/opt/devkitpro
export DEVKITARM=${DEVKITPRO}/devkitA64
export TOPdir=/workspace
export INSTALL_DIR=${TOPdir}/libs/ruby-switch
export RUBY_VER=3.2.2
export RUBY_SRC=${TOPdir}/ruby-${RUBY_VER}

echo ""
echo "Configuration:"
echo "  • Source:      ${RUBY_SRC}"
echo "  • Install to:  ${INSTALL_DIR}"
echo ""

# 2. Clean start
if [ -d "${RUBY_SRC}" ]; then
    rm -rf "${RUBY_SRC}"
fi
rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"

# 3. Download and Extract fresh
cd ${TOPdir}
if [ ! -f "${TOPdir}/ruby-${RUBY_VER}.tar.gz" ]; then
    echo ">>> Downloading Ruby ${RUBY_VER}..."
    wget https://cache.ruby-lang.org/pub/ruby/3.2/ruby-${RUBY_VER}.tar.gz -O "${TOPdir}/ruby-${RUBY_VER}.tar.gz"
fi

echo ">>> Extracting Ruby ${RUBY_VER}..."
tar -xf "${TOPdir}/ruby-${RUBY_VER}.tar.gz" -C "${TOPdir}"
cd ${RUBY_SRC}

# 4. Toolchain
# SPECS="/opt/devkitpro/libnx/switch.specs"
FLAGS="-march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIC -fno-plt -D__SWITCH__ -DRB_THREAD_LOCAL_SPECIFIER_IS_UNSUPPORTED -O2"
INCS="-I${DEVKITPRO}/libnx/include -I${DEVKITPRO}/portlibs/switch/include"


export PATH=${DEVKITARM}/bin:$PATH

# NO -specs here! specs is only for final executable linking
export CC="aarch64-none-elf-gcc ${FLAGS} ${INCS}"
export CXX="aarch64-none-elf-g++ ${FLAGS} ${INCS}"
export LD="aarch64-none-elf-ld"
export AR="aarch64-none-elf-ar"
export RANLIB="aarch64-none-elf-ranlib"
export STRIP="aarch64-none-elf-strip"
export OBJCOPY="aarch64-none-elf-objcopy"
export OBJDUMP="aarch64-none-elf-objdump"
export NM="aarch64-none-elf-nm"
export AS="aarch64-none-elf-as"
# Use gcc for shared linking to handle -Wl options correctly
export LDSHARED="aarch64-none-elf-gcc -shared ${FLAGS} ${INCS}"

# Create switch_shim.h with constants
cat > switch_shim.h <<'EOF'
#ifndef RUBY_SWITCH_SHIM_H
#define RUBY_SWITCH_SHIM_H
#ifdef __SWITCH__
#include <stddef.h>
#include <sys/types.h>

// mmap constants
#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define PROT_EXEC  0x4
#define PROT_NONE  0x0
#define MAP_SHARED  0x01
#define MAP_PRIVATE 0x02
#define MAP_FIXED   0x10
#define MAP_ANON    0x20
#define MAP_ANONYMOUS MAP_ANON
#define MAP_FAILED  ((void *)-1)

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
int munmap(void *addr, size_t length);
int mprotect(void *addr, size_t len, int prot);

// dl* function declarations (stubbed out on Switch)
void *dlopen(const char *filename, int flag);
int dlclose(void *handle);
void *dlsym(void *handle, const char *symbol);
char *dlerror(void);

#endif
#endif
EOF

# Create switch_shim.c with real implementations
cat > switch_shim.c <<'EOF'
#ifdef __SWITCH__
#include "switch_shim.h"
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/time.h>
#include <pthread.h>
#include <time.h>

uid_t getuid(void) { return 0; }
uid_t geteuid(void) { return 0; }
gid_t getgid(void) { return 0; }
gid_t getegid(void) { return 0; }

int pipe(int pipefd[2]) { return -1; }

int pthread_kill(pthread_t thread, int sig) { return 0; }

#include <string.h>
#include <sys/stat.h>

void *memmem(const void *haystack, size_t haystacklen, const void *needle, size_t needlelen) {
    if (!haystack || !needle || needlelen > haystacklen) return NULL;
    if (needlelen == 0) return (void *)haystack;
    const char *h = (const char *)haystack;
    const char *n = (const char *)needle;
    for (size_t i = 0; i <= haystacklen - needlelen; i++) {
        if (memcmp(h + i, n, needlelen) == 0) return (void *)(h + i);
    }
    return NULL;
}

mode_t umask(mode_t mask) { return 0; }

int execv(const char *path, char *const argv[]) { return -1; }

#include <sys/wait.h>
pid_t waitpid(pid_t pid, int *status, int options) { return -1; }

#include <pwd.h>
struct passwd *getpwnam(const char *name) { return NULL; }
struct passwd *getpwuid(uid_t uid) { return NULL; }
void endpwent(void) {}

#include <stdio.h>
FILE *popen(const char *command, const char *type) { return NULL; }
int pclose(FILE *stream) { return -1; }

int chown(const char *pathname, uid_t owner, gid_t group) { return 0; }
long sysconf(int name) { return -1; }
pid_t getppid(void) { return 0; }

#include <sys/resource.h>
int getrusage(int who, struct rusage *usage) { return -1; }

int execl(const char *path, const char *arg, ...) { return -1; }
int execle(const char *path, const char *arg, ...) { return -1; }

pid_t rb_mjit_fork(void) { return -1; }

// mmap stubs
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    (void)addr; (void)prot; (void)flags; (void)fd; (void)offset;
    return malloc(length);
}
int munmap(void *addr, size_t length) {
    (void)length;
    free(addr);
    return 0;
}
int mprotect(void *addr, size_t len, int prot) {
    (void)addr; (void)len; (void)prot;
    return 0;
}

// Note: ioctl, poll, and select are provided by libnx, so we don't stub them here
// The Ruby executable link may fail, but we only need the static library

// Comprehensive dl* stubs to prevent Ruby from trying to dynamically load anything
// These are needed even though we disabled MJIT, as Ruby's initialization may try to use them
void *dlopen(const char *filename, int flag) {
    (void)filename; (void)flag;
    return NULL;
}
int dlclose(void *handle) {
    (void)handle;
    return 0;
}
void *dlsym(void *handle, const char *symbol) {
    (void)handle; (void)symbol;
    return NULL;
}
char *dlerror(void) {
    return NULL;
}
#endif
EOF

# Compile switch_shim.c
echo ">>> Compiling switch_shim.c..."
${CC} -c switch_shim.c -o switch_shim.o

# Create minimal switch_shim.h for macros
cat > switch_shim.h <<'EOF'
#ifndef RUBY_SWITCH_SHIM_H
#define RUBY_SWITCH_SHIM_H

#ifdef __SWITCH__
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

void *memmem(const void *haystack, size_t haystacklen, const void *needle, size_t needlelen);

/* mmap/mprotect constants */
#ifndef MAP_FAILED
#define MAP_FAILED ((void*)-1)
#endif
#ifndef MAP_ANON
#define MAP_ANON 0
#endif
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS MAP_ANON
#endif
#ifndef MAP_PRIVATE
#define MAP_PRIVATE 0
#endif
#ifndef MAP_SHARED
#define MAP_SHARED 0
#endif
#ifndef PROT_NONE
#define PROT_NONE 0
#endif
#ifndef PROT_READ
#define PROT_READ 1
#endif
#ifndef PROT_WRITE
#define PROT_WRITE 2
#endif
#ifndef PROT_EXEC
#define PROT_EXEC 4
#endif

/* mmap function implementations */
static inline void* mmap(void *addr, size_t length, int prot, int flags, int fd, long offset) {
    (void)addr; (void)prot; (void)flags; (void)fd; (void)offset;
    void *mem = calloc(1, length);
    return mem ? mem : MAP_FAILED;
}

static inline int munmap(void *addr, size_t length) {
    (void)length;
    if (addr && addr != MAP_FAILED) {
        free(addr);
    }
    return 0;
}

static inline int mprotect(void *addr, size_t len, int prot) {
    (void)addr; (void)len; (void)prot;
    return 0;  /* Always succeed - Switch doesn't have memory protection */
}

/* Dynamic loading stubs */
#ifndef RTLD_NOW
#define RTLD_NOW 0
#endif
#ifndef RTLD_LOCAL
#define RTLD_LOCAL 0
#endif
#ifndef RTLD_DEFAULT
#define RTLD_DEFAULT ((void*)0)
#endif

typedef struct {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_saddr;
} Dl_info;

static inline void* dlopen(const char *filename, int flag) {
    (void)filename; (void)flag;
    return NULL;
}

static inline int dlclose(void *handle) {
    (void)handle;
    return 0;
}

static inline void* dlsym(void *handle, const char *symbol) {
    (void)handle; (void)symbol;
    return NULL;
}

static inline int dladdr(const void *addr, Dl_info *info) {
    (void)addr;
    if (info) {
        info->dli_fname = NULL;
        info->dli_fbase = NULL;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    return 0;
}

static inline char* dlerror(void) {
    return NULL;
}

#endif /* __SWITCH__ */
#endif /* RUBY_SWITCH_SHIM_H */
EOF

# Clear CFLAGS/LDFLAGS so they don't conflict with our CC definition
export CFLAGS=""
export CXXFLAGS=""
export LDFLAGS="-L${DEVKITPRO}/libnx/lib -L${DEVKITPRO}/portlibs/switch/lib"
export LIBS=""

# Remove test extensions to prevent shared object build failures
rm -rf ext/-test-

# 5. Configure
echo ">>> Configuring Ruby..."
./configure \
    --host=aarch64-none-elf \
    --target=aarch64-none-elf \
    --build=x86_64-pc-linux-gnu \
    --prefix="${TOPdir}/libs/ruby-switch" \
    --disable-install-doc \
    --disable-install-rdoc \
    --disable-install-capi \
    --disable-jit \
    --disable-shared \
    --enable-static \
    --with-compress-debug-sections=none \
    --with-out-ext=openssl,readline,dbm,gdbm,pty,syslog,fiddle,bigdecimal,-test- \
    ac_cv_func_fork=no \
    ac_cv_func_mmap=no \
    ac_cv_func_mprotect=no \
    ac_cv_func_sigaction=no \
    ac_cv_func_sigaltstack=no \
    ac_cv_func_sigprocmask=no \
    ac_cv_func_kill=no \
    ac_cv_func_dup=yes \
    ac_cv_func_dup2=yes \
    ac_cv_func_getuid=yes \
    ac_cv_func_geteuid=yes \
    ac_cv_func_getgid=yes \
    ac_cv_func_getegid=yes \
    ac_cv_func_pipe=yes \
    ac_cv_func_pthread_kill=yes \
    ac_cv_func_select=yes \
    ac_cv_func_poll=yes \
    ac_cv_func_memmem=yes \
    ac_cv_func_umask=yes \
    ac_cv_func_execv=yes \
    ac_cv_func_waitpid=yes \
    ac_cv_func_getpwnam=yes \
    ac_cv_func_endpwent=yes \
    ac_cv_func_popen=yes \
    ac_cv_func_pclose=yes \
    ac_cv_func_chown=yes \
    ac_cv_func_sysconf=yes \
    ac_cv_func_getppid=yes \
    ac_cv_func_getrusage=yes \
    ac_cv_func_execl=yes \
    ac_cv_func_execle=yes \
    ac_cv_func_ioctl=yes \
    ac_cv_header_sys_mman_h=no \
    ac_cv_func_dlopen=no \
    ac_cv_lib_dl_dlopen=no

[ $? -eq 0 ] || exit 1

# Patch Makefile to include switch_shim.o in libruby-static.a
echo ">>> Patching Makefile to include switch_shim.o..."
sed -i 's|^LIBRUBY_A_OBJS = |LIBRUBY_A_OBJS = switch_shim.o |' Makefile
sed -i 's|^SOLIBS = |SOLIBS = -lnx |' Makefile

# Patch DLDFLAGS to link libnx for Ruby executable (provides select, poll, ioctl)
# This allows the Ruby executable to link successfully, though we don't actually need it
echo ">>> Patching Makefile to link libnx for Ruby executable..."
if ! grep -q "SWITCH_LIBNX_PATCH" Makefile; then
    # Add -lnx to DLDFLAGS so select/poll/ioctl are available during Ruby executable link
    sed -i 's|^DLDFLAGS = \(.*\)|DLDFLAGS = \1 -lnx|' Makefile
    echo "  ✓ Patched DLDFLAGS to include -lnx"
fi

# 6. Patch
echo ""
echo ">>> Patching for Switch..."

# Apply shim to all files that need it
for F in cont.c io_buffer.c gc.c vm.c addr2line.c thread.c thread_pthread.c; do
    if [ -f "$F" ]; then
        echo "    → Patching $F (adding shim and disabling sys/mman.h)"
        sed -i '1i#include "switch_shim.h"' "$F"
        sed -i 's|#include <sys/mman\.h>|/* #include <sys/mman.h> */|g' "$F"
    fi
done

# Patch io.c for setmode (Windows-only function)
if [ -f io.c ]; then
    echo "    → Patching io.c (disabling setmode)"
    sed -i '1i#ifdef _WIN32' io.c
    sed -i '2i#define HAVE_SETMODE 1' io.c
    sed -i '3i#else' io.c
    sed -i '4i#define setmode(fd, mode) ((void)0)' io.c
    sed -i '5i#endif' io.c
fi

# # Patch thread.c and thread_pthread.c for signal functions
# if [ -f thread.c ]; then
#     echo "    → Patching thread.c (disabling posix_signal)"
#     # Stub out posix_signal for Switch
#     sed -i '1i#ifdef __SWITCH__' thread.c
#     sed -i '2i#define posix_signal(sig, func) ((void)0)' thread.c
#     sed -i '3i#endif' thread.c
# fi

if [ -f thread_pthread.c ]; then
    echo "    → Patching thread_pthread.c (disabling posix_signal)"
    sed -i '1i#ifdef __SWITCH__' thread_pthread.c
    sed -i '2i#define posix_signal(sig, func) ((void)0)' thread_pthread.c
    sed -i '3i#endif' thread_pthread.c
fi

# Patch mjit.c to disable dynamic loading on Switch (comprehensive)
if [ -f mjit.c ]; then
    echo "    → Patching mjit.c (comprehensive dl* stub)"
    # Add Switch-specific stubs at the beginning
    cat > mjit_switch_stub.h << 'MJIT_EOF'
#ifdef __SWITCH__
/* MJIT disabled on Switch - stub out all dynamic loading */
#define dlopen(file, mode) ((void*)0)
#define dlclose(handle) (0)
#define dlsym(handle, symbol) ((void*)0)
#define dlerror() ("MJIT disabled on Nintendo Switch")
#define RTLD_NOW 0
#define RTLD_DEFAULT ((void*)0)
#endif
MJIT_EOF
    sed -i '1i#include "mjit_switch_stub.h"' mjit.c
    sed -i 's|#include <dlfcn.h>|#ifndef __SWITCH__\n#include <dlfcn.h>\n#endif|g' mjit.c
fi

# file.c patch
if [ -f file.c ]; then
    echo "    → Patching file.c"
    sed -i '1i#ifndef SHORT2NUM\n#define SHORT2NUM(x) INT2NUM((int)x)\n#endif' file.c
fi

# Disable signal handler functions with Python (more reliable than sed/awk)
echo "    → Disabling signal handlers in gc.c..."

python3 << 'PYTHON_EOF'
import re

with open('gc.c', 'r') as f:
    content = f.read()

# Wrap read_barrier_signal function
content = re.sub(
    r'(static void\s+read_barrier_signal\s*\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\})',
    r'#ifndef __SWITCH__\n\1\n#else\nstatic void read_barrier_signal(MAYBE_UNUSED(int sig), MAYBE_UNUSED(siginfo_t *info), MAYBE_UNUSED(void *ctx)) { /* no-op for Switch */ }\n#endif',
    content,
    flags=re.DOTALL
)

# Wrap install_handlers function
content = re.sub(
    r'(static void\s+install_handlers\s*\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\})',
    r'#ifndef __SWITCH__\n\1\n#else\nstatic void install_handlers(void) { /* no-op for Switch */ }\n#endif',
    content,
    flags=re.DOTALL
)

# Wrap uninstall_handlers function
content = re.sub(
    r'(static void\s+uninstall_handlers\s*\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\})',
    r'#ifndef __SWITCH__\n\1\n#else\nstatic void uninstall_handlers(void) { /* no-op for Switch */ }\n#endif',
    content,
    flags=re.DOTALL
)

with open('gc.c', 'w') as f:
    f.write(content)

print("    ✓ Signal handlers wrapped with #ifndef __SWITCH__")
PYTHON_EOF


echo "    ✓ All patches applied"

# 7. Build - only build the static library, skip extensions
echo ""
# 7. Build
echo ">>> Building Ruby..."
echo "  ℹ️  Note: Ruby executable link will fail (undefined select/poll) - this is EXPECTED and harmless."
echo "  ℹ️  We only need the static library (libruby-static.a), not the executable."
echo ""
# Use -k flag to keep going even if some targets fail (like the ruby executable)
# This allows the static library to be built even if executable linking fails
make -k -j$(nproc) || {
    echo ""
    echo "⚠️  Build had errors (expected for ruby executable), checking for static library..."
}

# make install might fail due to ruby executable linking error, but we only need the static lib
make install || echo "make install failed (expected due to missing symbols in executable), continuing..."

# Ensure library is copied
mkdir -p "${INSTALL_DIR}/lib"
if [ ! -f "${INSTALL_DIR}/lib/libruby-static.a" ]; then
    if [ -f "libruby-static.a" ]; then
        cp libruby-static.a "${INSTALL_DIR}/lib/"
    else
        echo "ERROR: libruby-static.a not found in build directory!"
        exit 1
    fi
fi

# Repack with extensions
echo ">>> Repacking libruby-static.a with extensions..."

# We need ext/extinit.o specifically.
EXTINIT="ext/extinit.o"
if [ -f "$EXTINIT" ]; then
    echo "    Adding $EXTINIT"
    ${AR} q "${INSTALL_DIR}/lib/libruby-static.a" "$EXTINIT"
else
    echo "WARNING: $EXTINIT not found! Extensions may not load."
fi

# Add switch_shim.o
if [ -f "switch_shim.o" ]; then
    echo "    Adding switch_shim.o"
    ${AR} q "${INSTALL_DIR}/lib/libruby-static.a" "switch_shim.o"
fi

# Find all other extension objects
# We look for .o files in ext/ and enc/ that are NOT extinit.o
echo "    Adding extension objects..."
find ext -name "*.o" ! -name "extinit.o" -exec ${AR} q "${INSTALL_DIR}/lib/libruby-static.a" {} + 2>/dev/null || true
find enc -name "*.o" -exec ${AR} q "${INSTALL_DIR}/lib/libruby-static.a" {} + 2>/dev/null || true

# Re-index
${RANLIB} "${INSTALL_DIR}/lib/libruby-static.a"

# 8. Install Headers (Manual copy if make install failed)
echo ">>> Installing headers..."
mkdir -p "${INSTALL_DIR}/include/ruby-3.2.0"
# Try make install (will partially fail, that's OK)
make install 2>&1 | tee install.log || true

# Ensure library is there
if [ ! -f "${INSTALL_DIR}/lib/libruby-static.a" ]; then
    echo "    → Manually copying library..."
    mkdir -p "${INSTALL_DIR}/lib"
    cp -v libruby-static.a "${INSTALL_DIR}/lib/"
fi

# ✅ CRITICAL: Manually copy ALL headers with proper structure
echo "    → Ensuring all headers are installed..."

# Ruby puts headers in .ext/include during build
if [ -d ".ext/include/ruby-3.2.0" ]; then
    echo "    → Copying from .ext/include/ruby-3.2.0/"
    mkdir -p "${INSTALL_DIR}/include"
    cp -r .ext/include/ruby-3.2.0 "${INSTALL_DIR}/include/" 2>/dev/null || true
fi

# Also need the main include/ directory for additional headers
if [ -d "include" ]; then
    echo "    → Merging from source include/"
    # Copy top-level headers
    cp -r include/*.h "${INSTALL_DIR}/include/ruby-3.2.0/" 2>/dev/null || true
    
    # Copy ruby/ subdirectory if it exists
    if [ -d "include/ruby" ]; then
        mkdir -p "${INSTALL_DIR}/include/ruby-3.2.0/ruby"
        cp -r include/ruby/* "${INSTALL_DIR}/include/ruby-3.2.0/ruby/" 2>/dev/null || true
    fi
fi

# Architecture-specific headers
if [ -d ".ext/include/aarch64-elf" ]; then
    echo "    → Copying architecture headers..."
    cp -r .ext/include/aarch64-elf "${INSTALL_DIR}/include/ruby-3.2.0/" 2>/dev/null || true
fi

echo "✓ Install complete"

# 9. Verify installation
echo ""
echo "🔍 Verifying installation..."

ERRORS=0

# Check library
if [ ! -f "${INSTALL_DIR}/lib/libruby-static.a" ]; then
    echo "❌ Library not found: ${INSTALL_DIR}/lib/libruby-static.a"
    ERRORS=1
else
    SIZE_MB=$(( $(stat -c%s "${INSTALL_DIR}/lib/libruby-static.a") / 1024 / 1024 ))
    echo "✅ Library: libruby-static.a (${SIZE_MB} MB)"
fi

# Check headers
if [ ! -d "${INSTALL_DIR}/include/ruby-3.2.0" ]; then
    echo "❌ Headers not found: ${INSTALL_DIR}/include/ruby-3.2.0"
    echo ""
    echo "Current structure:"
    find "${INSTALL_DIR}/include" -maxdepth 2 -type d 2>/dev/null || echo "  (empty)"
    ERRORS=1
else
    echo "✅ Headers: ruby-3.2.0/"
    
    # Check for architecture-specific headers
    ARCH_HEADERS=$(find "${INSTALL_DIR}/include/ruby-3.2.0" -name "config.h" | head -1)
    if [ -n "$ARCH_HEADERS" ]; then
        echo "✅ Arch headers: $(dirname $ARCH_HEADERS | xargs basename)"
    else
        echo "⚠️  Architecture-specific headers not found (may cause issues)"
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "❌ Installation incomplete!"
    exit 1
fi

# Success!
echo ""    
    echo "════════════════════════════════════════════════════════════"
echo "  ✅ Ruby 3.2.2 Built Successfully!"
    echo "════════════════════════════════════════════════════════════"
    echo ""
echo "Library:  ${INSTALL_DIR}/lib/libruby-static.a (${SIZE_MB} MB)"
echo "Headers:  ${INSTALL_DIR}/include/ruby-3.2.0/"
echo ""
echo "Next: cd /workspace/switch/buildScripts && ./build_mkxpz_switch.sh"
echo ""