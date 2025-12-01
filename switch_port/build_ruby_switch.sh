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
if [ ! -f "ruby-${RUBY_VER}.tar.gz" ]; then
    echo ">>> Downloading Ruby ${RUBY_VER}..."
    wget https://cache.ruby-lang.org/pub/ruby/3.2/ruby-${RUBY_VER}.tar.gz
fi

echo ">>> Extracting Ruby ${RUBY_VER}..."
tar -xf ruby-${RUBY_VER}.tar.gz
cd ${RUBY_SRC}

# 4. Toolchain
SPECS="/opt/devkitpro/libnx/switch.specs"
FLAGS="-march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIE -D__SWITCH__ -O2"
INCS="-I${DEVKITPRO}/libnx/include -I${DEVKITPRO}/portlibs/switch/include"
LIBS_PATH="-L${DEVKITPRO}/libnx/lib -L${DEVKITPRO}/portlibs/switch/lib"

export PATH=${DEVKITARM}/bin:$PATH

# Embed flags into CC so 'configure' can't ignore them
export CC="aarch64-none-elf-gcc -specs=${SPECS} ${FLAGS} ${INCS} ${LIBS_PATH}"
export CXX="aarch64-none-elf-g++ -specs=${SPECS} ${FLAGS} ${INCS} ${LIBS_PATH}"
export AR=aarch64-none-elf-gcc-ar
export RANLIB=aarch64-none-elf-gcc-ranlib
export LD=aarch64-none-elf-ld

# Clear CFLAGS/LDFLAGS so they don't conflict with our CC definition
export CFLAGS=""
export CXXFLAGS=""
export LDFLAGS="" 
# Force linking against libnx
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

# Complete mmap/mprotect shim
cat > switch_shim.h <<'EOF'
#ifndef RUBY_SWITCH_SHIM_H
#define RUBY_SWITCH_SHIM_H

#ifdef __SWITCH__
#include <stdlib.h>
#include <stddef.h>

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

/* Function implementations */
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

#endif /* __SWITCH__ */
#endif /* RUBY_SWITCH_SHIM_H */
EOF

echo "    → Created switch_shim.h"

# Apply shim to all files that need it
for F in cont.c io_buffer.c gc.c; do
    if [ -f "$F" ]; then
        echo "    → Patching $F (adding shim)"
        sed -i '1i#include "switch_shim.h"' "$F"
        # Comment out sys/mman.h
        sed -i 's|#include <sys/mman\.h>|/* #include <sys/mman.h> */|g' "$F"
    fi
done

# file.c patch
if [ -f file.c ]; then
    echo "    → Patching file.c"
    sed -i '1i#ifndef SHORT2NUM\n#define SHORT2NUM(x) INT2NUM((int)x)\n#endif' file.c
fi

# ✅ FINAL SOLUTION: Use awk to wrap entire signal handler block
echo "    → Completely disabling signal handlers in gc.c..."

awk '
BEGIN { in_block = 0; skip_until_endif = 0 }

# Detect start of signal handler platform block
/^#if.*HAVE_WORKING_FORK/ {
    print "#ifndef __SWITCH__  /* Signal handlers disabled for Switch */"
    print "#if 0  /* Original signal code disabled */"
    in_block = 1
    skip_until_endif = 1
    next
}

# Track #endif depth
/^#endif/ && in_block {
    print
    if (skip_until_endif) {
        skip_until_endif--
        if (skip_until_endif == 0) {
            print "#endif  /* __SWITCH__ */"
            print ""
            print "#ifdef __SWITCH__"
            print "/* Stub implementations for Nintendo Switch */"
            print "static void install_handlers(void) { /* no-op */ }"
            print "static void uninstall_handlers(void) { /* no-op */ }"
            print "#endif  /* __SWITCH__ */"
            in_block = 0
        }
    }
    next
}

# Track nested #ifs
/^#if/ && in_block { skip_until_endif++ }

# Print all other lines
{ print }
' gc.c > gc.c.tmp && mv gc.c.tmp gc.c

echo "    ✓ All patches applied"

# 7. Build
echo ""
echo ">>> Building (5-10 min)..."
make -j$(nproc) 2>&1 | tee build.log

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Build failed!"
    echo ""
    grep "error:" build.log | tail -20
    exit 1
fi

# 8. Install
echo ""
echo ">>> Installing..."
make install 2>&1 | tee install.log
[ $? -eq 0 ] || exit 1

# 9. Verify
if [ -f "${INSTALL_DIR}/lib/libruby-static.a" ]; then
    SIZE_MB=$(( $(stat -c%s "${INSTALL_DIR}/lib/libruby-static.a") / 1024 / 1024 ))
echo ""    
    echo "════════════════════════════════════════════════════════════"
    echo "  ✅ Ruby Built Successfully! (${SIZE_MB} MB)"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "${INSTALL_DIR}/lib/libruby-static.a"
        echo ""
    echo "Next: cd /workspace/switch_port && ./build_mkxpz_switch.sh"
    echo ""
else
    echo "❌ Library missing!"
        exit 1
fi