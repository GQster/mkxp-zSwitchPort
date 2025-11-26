#!/bin/bash
set -e

# 1. Setup Paths
export DEVKITPRO=/opt/devkitpro
export DEVKITARM=${DEVKITPRO}/devkitA64
export TOPdir=$(pwd)
export INSTALL_DIR=${TOPdir}/libs/ruby-switch
export RUBY_VER=3.2.2

# 2. Clean start
if [ -d "ruby-${RUBY_VER}" ]; then
    echo ">>> Cleaning up old source tree..."
    rm -rf "ruby-${RUBY_VER}"
fi

# 3. Download and Extract fresh
if [ ! -f "ruby-${RUBY_VER}.tar.gz" ]; then
    wget https://cache.ruby-lang.org/pub/ruby/3.2/ruby-${RUBY_VER}.tar.gz
fi
echo ">>> Extracting Ruby ${RUBY_VER}..."
tar -xf ruby-${RUBY_VER}.tar.gz
cd ruby-${RUBY_VER}

# 4. Toolchain
SPECS="/opt/devkitpro/libnx/switch.specs"
FLAGS="-march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIE -D__SWITCH__ -O3 -g"
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
    ac_cv_func_spawnv=no \
    ac_cv_func_execve=no \
    ac_cv_func_getrlimit=no \
    ac_cv_func_setrlimit=no \
    ac_cv_lib_crypt_crypt=no \
    ac_cv_func_dlopen=no \
    ac_cv_func_isnan=yes \
    ac_cv_func_isinf=yes \
    rb_cv_type_context=ucontext \
    ac_cv_header_sys_mman_h=no \
    ac_cv_func_mmap=no \
    ac_cv_func_mprotect=no \
    ac_cv_func_sigaction=no \
    ac_cv_func_sigaltstack=no \
    ac_cv_func_sigprocmask=no \
    ac_cv_func_kill=no

# 5.5 Patches -------------------------------------------------
echo ">>> Injecting Switch shim..."

read -r -d '' SHIM <<'EOF'
#ifdef __SWITCH__
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#define mmap(a,b,c,d,e,f) calloc(1,b)
#define munmap(a,b) free(a)
#define mprotect(a,b,c) 0
#define MAP_FAILED NULL
#define PROT_READ 1
#define PROT_WRITE 2
#define PROT_NONE 0
#define PROT_EXEC 4
#define MAP_PRIVATE 0
#define MAP_ANON 0
#define MAP_ANONYMOUS 0
#define MAP_FIXED 0
#define MAP_SHARED 0
/* Disable signal / guard-page GC behaviour */
#define USE_SIGALTSTACK 0
#define USE_GC_PAGE_PROTECTION 0
#endif
EOF

# prepend shim safely before includes
for F in cont.c io_buffer.c gc.c; do
  echo "    → patching $F"
  { printf "%s\n" "$SHIM"; cat "$F"; } > "${F}.tmp" && mv "${F}.tmp" "$F"
  sed -i 's|#include <sys/mman.h>|/* skipped: sys/mman.h */|' "$F"
done

# Fix for missing SHORT2NUM in file.c
sed -i '1s|^|#define SHORT2NUM(x) INT2NUM((int)x)\n|' file.c

# 6. Build
echo ">>> Building Ruby..."
make -j"$(nproc)"

echo ">>> Installing..."
make install

echo
echo "=== SUCCESS ==="
echo "Static library ready at: ${INSTALL_DIR}/lib/libruby-static.a"