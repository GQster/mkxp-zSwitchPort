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
FLAGS="-march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIC -fno-plt -D__SWITCH__ -O2"
INCS="-I${DEVKITPRO}/libnx/include -I${DEVKITPRO}/portlibs/switch/include"

export PATH=${DEVKITARM}/bin:$PATH

# NO -specs here! specs is only for final executable linking
export CC="aarch64-none-elf-gcc ${FLAGS} ${INCS}"
export CXX="aarch64-none-elf-g++ ${FLAGS} ${INCS}"
export AR=aarch64-none-elf-gcc-ar
export RANLIB=aarch64-none-elf-gcc-ranlib
export LD=aarch64-none-elf-ld

# Clear CFLAGS/LDFLAGS so they don't conflict with our CC definition
export CFLAGS=""
export CXXFLAGS=""
export LDFLAGS="-L${DEVKITPRO}/libnx/lib -L${DEVKITPRO}/portlibs/switch/lib"
export LIBS="-lnx"

# 5. Configure
echo ">>> Configuring Ruby..."
./configure \
    --host=aarch64-none-elf \
    --build=x86_64-linux-gnu \
    --prefix=${INSTALL_DIR} \
    --disable-install-doc \
    --disable-jit \
    --disable-shared \
    --enable-static \
    --with-static-linked-ext \
    --with-baseruby=$(which ruby) \
    --without-gmp \
    --with-out-ext=openssl,readline,dbm,gdbm,fiddle,pty,syslog,sdbm,socket \
    ac_cv_func_fork=no \
    ac_cv_func_mmap=no \
    ac_cv_func_mprotect=no \
    ac_cv_func_sigaction=no \
    ac_cv_func_sigaltstack=no \
    ac_cv_func_sigprocmask=no \
    ac_cv_func_kill=no \
    ac_cv_header_sys_mman_h=no

[ $? -eq 0 ] || exit 1

# 6. Patch
echo ""
echo ">>> Patching for Switch..."

# Complete mmap/mprotect and dl* shim
cat > switch_shim.h <<'EOF'
#ifndef RUBY_SWITCH_SHIM_H
#define RUBY_SWITCH_SHIM_H

#ifdef __SWITCH__
#include <stdlib.h>
#include <stddef.h>
#include <sys/time.h>

/* Poll constants and structures */
#define POLLIN     0x0001
#define POLLOUT    0x0004
#define POLLERR    0x0008
#define POLLHUP    0x0010
#define POLLNVAL   0x0020

typedef unsigned int nfds_t;

struct pollfd {
    int   fd;
    short events;
    short revents;
};

/* Poll stub - just sleep for timeout */
static inline int poll(struct pollfd *fds, nfds_t nfds, int timeout) {
    (void)fds;
    (void)nfds;
    if (timeout > 0) {
        struct timeval tv;
        tv.tv_sec = timeout / 1000;
        tv.tv_usec = (timeout % 1000) * 1000;
        select(0, NULL, NULL, NULL, &tv);
    }
    return 0;
}

static inline int ppoll(struct pollfd *fds, nfds_t nfds, 
                        const struct timespec *timeout, const void *sigmask) {
    (void)sigmask;
    int timeout_ms = -1;
    if (timeout) {
        timeout_ms = timeout->tv_sec * 1000 + timeout->tv_nsec / 1000000;
    }
    return poll(fds, nfds, timeout_ms);
}

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

/* Dynamic loading stubs (for addr2line.c, mjit.c, etc.) */
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
    return NULL;  /* No dynamic loading on Switch */
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
    return 0;  /* Could not find symbol */
}

static inline char* dlerror(void) {
    return NULL;
}

#endif /* __SWITCH__ */
#endif /* RUBY_SWITCH_SHIM_H */
EOF

echo "    → Created switch_shim.h"

# Apply shim to all files that need it
for F in cont.c io_buffer.c gc.c vm.c addr2line.c thread.c thread_pthread.c; do
    if [ -f "$F" ]; then
        echo "    → Patching $F (adding shim)"
        sed -i '1i#include "switch_shim.h"' "$F"
        # Comment out sys/mman.h
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
echo ">>> Building static library (5-10 min)..."
make -j$(nproc) libruby-static.a 2>&1 | tee build.log

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Build failed!"
    echo ""
    grep "error:" build.log | tail -20
    exit 1
fi

echo ""
echo ">>> Building encodings..."
make -j$(nproc) enc 2>&1 | tee -a build.log || true  # Encodings may partially fail, that's ok

# 8. Install headers and library
echo ""
echo ">>> Installing Ruby..."

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
echo "Next: cd /workspace/switch_port && ./build_mkxpz_switch.sh"
echo ""