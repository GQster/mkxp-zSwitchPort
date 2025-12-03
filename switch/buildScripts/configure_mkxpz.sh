#!/bin/bash
set -e

# 1. Setup Paths
export TOPDIR=$(pwd)
export DEVKITPRO=/opt/devkitpro
export DEVKITARM=${DEVKITPRO}/devkitA64
export LIBS_DIR=${TOPDIR}/libs

export PATH=${DEVKITARM}/bin:$PATH

# Common Flags for Switch
export CFLAGS="-march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIC -D__SWITCH__ -Dunix -DPHYSFS_NO_CDROM_SUPPORT=1 -I${DEVKITPRO}/libnx/include -I${DEVKITPRO}/portlibs/switch/include"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-specs=${DEVKITPRO}/libnx/switch.specs -march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIC -L${DEVKITPRO}/libnx/lib -L${DEVKITPRO}/portlibs/switch/lib -lnx -lm"

mkdir -p "${LIBS_DIR}"

# ────────────────────────────────────────────────────────────
# 0. Patch SDL2 pkg-config: remove bogus libs
# ────────────────────────────────────────────────────────────
echo ">>> Patching SDL2 pkg-config to remove invalid libraries..."
SDL2_PC="${DEVKITPRO}/portlibs/switch/lib/pkgconfig/sdl2.pc"
if [ -f "${SDL2_PC}" ]; then
    sed -i 's/-lEGL -lglapi -ldrm_nouveau//g' "${SDL2_PC}"
    echo "Patched ${SDL2_PC}"
else
    echo "ERROR: ${SDL2_PC} not found!"
    exit 1
fi

# ────────────────────────────────────────────────────────────
# 1. Build PhysicsFS
# ────────────────────────────────────────────────────────────
echo ">>> Building PhysicsFS for Switch..."
if [ ! -d "${TOPDIR}/physfs-src" ]; then
    git clone --depth 1 --branch release-3.2.0 https://github.com/icculus/physfs.git "${TOPDIR}/physfs-src"
    sed -i '/#elif defined(__APPLE__)/i #elif defined(__SWITCH__)\n#  define PHYSFS_PLATFORM_UNIX' "${TOPDIR}/physfs-src/src/physfs_platforms.h"
fi
rm -rf "${TOPDIR}/physfs-build"

# ────────────────────────────────────────────────────────────
# Patch PhysFS for Nintendo Switch (idempotent)
# Hardcode base/pref directory so PHYSFS_init doesn't fail.
# ────────────────────────────────────────────────────────────
PHYSFS_UNIX_C="${TOPDIR}/physfs-src/src/physfs_platform_unix.c"

if ! grep -q "PHYSFS_SWITCH_BASEDIR_PATCH" "$PHYSFS_UNIX_C"; then
    echo ">>> Applying Switch PhysFS base/pref dir patch..."

    # Insert override into __PHYSFS_platformCalcBaseDir
    sed -i '/char *__PHYSFS_platformCalcBaseDir/a \
/* PHYSFS_SWITCH_BASEDIR_PATCH */\
#ifdef __SWITCH__\
    const char *basePath = "sdmc:/switch/mkxp-z/";\
    char *retval = (char *) allocator.Malloc(strlen(basePath) + 1);\
    if (retval) strcpy(retval, basePath);\
    return retval;\
#endif\
' "$PHYSFS_UNIX_C"

    # Insert override into __PHYSFS_platformCalcPrefDir
    sed -i '/char *__PHYSFS_platformCalcPrefDir/a \
/* PHYSFS_SWITCH_BASEDIR_PATCH */\
#ifdef __SWITCH__\
    const char *prefPath = "sdmc:/switch/mkxp-z/";\
    char *retval = (char *) allocator.Malloc(strlen(prefPath) + 1);\
    if (retval) strcpy(retval, prefPath);\
    return retval;\
#endif\
' "$PHYSFS_UNIX_C"

else
    echo ">>> Switch PhysFS patch already applied."
fi

cmake -S "${TOPDIR}/physfs-src" -B "${TOPDIR}/physfs-build" \
    -DCMAKE_SYSTEM_NAME=Generic \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=${DEVKITARM}/bin/aarch64-none-elf-gcc \
    -DCMAKE_CXX_COMPILER=${DEVKITARM}/bin/aarch64-none-elf-g++ \
    -DCMAKE_AR=${DEVKITARM}/bin/aarch64-none-elf-gcc-ar \
    -DCMAKE_RANLIB=${DEVKITARM}/bin/aarch64-none-elf-gcc-ranlib \
    -DCMAKE_FIND_ROOT_PATH=${DEVKITPRO}/portlibs/switch \
    -DPHYSFS_BUILD_SHARED=OFF \
    -DPHYSFS_BUILD_STATIC=ON \
    -DPHYSFS_BUILD_TEST=OFF \
    -DCMAKE_INSTALL_PREFIX=${LIBS_DIR}/physfs-switch \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS}"

make -C physfs-build -j"$(nproc)"
make -C physfs-build install

# ────────────────────────────────────────────────────────────
# 2. Build SDL_sound
# ────────────────────────────────────────────────────────────
echo ">>> Building SDL_sound for Switch..."
if [ ! -d "${TOPDIR}/SDL_sound-src" ]; then
    git clone --depth 1 --branch v2.0.1 https://github.com/icculus/SDL_sound.git "${TOPDIR}/SDL_sound-src"
fi

echo ">>> Removing all SDL_sound example targets and references..."
# Remove any line referencing playsound or playsound_simple
sed -i '/playsound/d' "${TOPDIR}/SDL_sound-src/CMakeLists.txt"
sed -i '/playsound_simple/d' "${TOPDIR}/SDL_sound-src/CMakeLists.txt"

rm -rf "${TOPDIR}/SDL_sound-build"

cmake -S "${TOPDIR}/SDL_sound-src" -B "${TOPDIR}/SDL_sound-build" \
    -DCMAKE_SYSTEM_NAME=Generic \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=${DEVKITARM}/bin/aarch64-none-elf-gcc \
    -DCMAKE_CXX_COMPILER=${DEVKITARM}/bin/aarch64-none-elf-g++ \
    -DCMAKE_AR=${DEVKITARM}/bin/aarch64-none-elf-gcc-ar \
    -DCMAKE_RANLIB=${DEVKITARM}/bin/aarch64-none-elf-gcc-ranlib \
    -DCMAKE_FIND_ROOT_PATH=${DEVKITPRO}/portlibs/switch \
    -DSDL2_INCLUDE_DIR=${DEVKITPRO}/portlibs/switch/include/SDL2 \
    -DSDL2_LIBRARY=${DEVKITPRO}/portlibs/switch/lib/libSDL2.a \
    -DSDL_SOUND_BUILD_SHARED=OFF \
    -DSDL_SOUND_BUILD_STATIC=ON \
    -DSDL_SOUND_BUILD_TEST=OFF \
    -DCMAKE_INSTALL_PREFIX=${LIBS_DIR}/SDL_sound-switch \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="-specs=${DEVKITPRO}/libnx/switch.specs -L${DEVKITPRO}/libnx/lib -L${DEVKITPRO}/portlibs/switch/lib -lnx -lm"

make -C "${TOPDIR}/SDL_sound-build" -j"$(nproc)"
make -C "${TOPDIR}/SDL_sound-build" install

echo
echo "✅ Dependency build complete!"
echo "→ PhysicsFS: ${LIBS_DIR}/physfs-switch/lib/libphysfs.a"
echo "→ SDL_sound: ${LIBS_DIR}/SDL_sound-switch/lib/libSDL2_sound.a"