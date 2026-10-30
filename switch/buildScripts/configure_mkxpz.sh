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
if [ -f "${SDL2_PC}" ] && [ ! -w "${SDL2_PC}" ]; then
    # Non-root container (docker_build.sh): the image's file is read-only.
    # Current devkitPro sdl2.pc no longer has this exact sequence anyway.
    echo "Skipping ${SDL2_PC} patch (not writable)"
elif [ -f "${SDL2_PC}" ]; then
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
# Patch PhysFS platforms.h to recognize Nintendo Switch (idempotent)
# ────────────────────────────────────────────────────────────
PHYSFS_PLATFORMS_H="${TOPDIR}/physfs-src/src/physfs_platforms.h"

if ! grep -q "__SWITCH__" "$PHYSFS_PLATFORMS_H"; then
    echo ">>> Applying Switch platform definition patch to physfs_platforms.h..."
    sed -i '/#elif defined(__QNX__)/i #elif defined(__SWITCH__)\n#  define PHYSFS_NO_CDROM_SUPPORT 1\n#  define PHYSFS_PLATFORM_UNIX 1\n#  define PHYSFS_PLATFORM_POSIX 1' "$PHYSFS_PLATFORMS_H"
else
    echo ">>> Switch platform definition already in physfs_platforms.h"
fi

# ────────────────────────────────────────────────────────────
# Patch PhysFS for Nintendo Switch (idempotent)
# Return "./" to let PhysFS use current directory.
# PhysFS requires paths to end with a directory separator.
# This works in both Ryujinx (current dir) and real Switch (libnx sets cwd).
# ────────────────────────────────────────────────────────────
PHYSFS_UNIX_C="${TOPDIR}/physfs-src/src/physfs_platform_unix.c"

if ! grep -q "PHYSFS_SWITCH_BASEDIR_PATCH" "$PHYSFS_UNIX_C"; then
    echo ">>> Applying Switch PhysFS base/pref dir patch..."

    # Patch __PHYSFS_platformCalcBaseDir - insert right after opening brace
    sed -i '/^char \*__PHYSFS_platformCalcBaseDir(const char \*argv0)$/,/^{$/ {
        /^{$/a\
/* PHYSFS_SWITCH_BASEDIR_PATCH */\
#ifdef __SWITCH__\
    /* On Switch, return "./" to use current directory. */\
    /* PhysFS requires the path to end with a directory separator. */\
    char *switch_retval = (char *) allocator.Malloc(3);\
    if (switch_retval) strcpy(switch_retval, "./");\
    return switch_retval;\
#endif
    }' "$PHYSFS_UNIX_C"

    # Patch __PHYSFS_platformCalcPrefDir - insert right after opening brace
    sed -i '/^char \*__PHYSFS_platformCalcPrefDir(const char \*org, const char \*app)$/,/^{$/ {
        /^{$/a\
/* PHYSFS_SWITCH_BASEDIR_PATCH */\
#ifdef __SWITCH__\
    /* On Switch, return "./" to use current directory. */\
    /* PhysFS requires the path to end with a directory separator. */\
    char *switch_retval = (char *) allocator.Malloc(3);\
    if (switch_retval) strcpy(switch_retval, "./");\
    return switch_retval;\
#endif
    }' "$PHYSFS_UNIX_C"

else
    echo ">>> Switch PhysFS patch already applied."
fi

# ────────────────────────────────────────────────────────────
# Add debug logging to PHYSFS_init for Switch (idempotent)
# ────────────────────────────────────────────────────────────
PHYSFS_C="${TOPDIR}/physfs-src/src/physfs.c"

if ! grep -q "PHYSFS_SWITCH_DEBUG_PATCH" "$PHYSFS_C"; then
    echo ">>> Adding debug logging to PHYSFS_init..."
    
    # Add debug logging at the start of PHYSFS_init
    sed -i '/^int PHYSFS_init(const char \*argv0)$/,/^{$/ {
        /^{$/a\
/* PHYSFS_SWITCH_DEBUG_PATCH */\
#ifdef __SWITCH__\
    printf("PHYSFS_init: enter, argv0=%s\\n", argv0 ? argv0 : "(null)");\
    fflush(stdout);\
#endif
    }' "$PHYSFS_C"
    
    # Add debug logging before platformInit
    sed -i 's/if (!__PHYSFS_platformInit())/\
#ifdef __SWITCH__\
    printf("PHYSFS_init: before platformInit\\n"); fflush(stdout);\
#endif\
    if (!__PHYSFS_platformInit())/g' "$PHYSFS_C"

    # Add debug logging before calculateBaseDir
    sed -i 's/baseDir = calculateBaseDir(argv0);/\
#ifdef __SWITCH__\
    printf("PHYSFS_init: before calculateBaseDir\\n"); fflush(stdout);\
#endif\
    baseDir = calculateBaseDir(argv0);\
#ifdef __SWITCH__\
    printf("PHYSFS_init: baseDir=%s\\n", baseDir ? baseDir : "(null)"); fflush(stdout);\
#endif/g' "$PHYSFS_C"

    # Add debug logging to initializeMutexes failure
    sed -i 's/if (!initializeMutexes()) goto initFailed;/\
#ifdef __SWITCH__\
    printf("PHYSFS_init: calling initializeMutexes\\n"); fflush(stdout);\
#endif\
    if (!initializeMutexes()) {\
#ifdef __SWITCH__\
        printf("PHYSFS_init: initializeMutexes FAILED\\n"); fflush(stdout);\
#endif\
        goto initFailed;\
    }/g' "$PHYSFS_C"
    
else
    echo ">>> PhysFS debug logging already added."
fi

# ────────────────────────────────────────────────────────────
# Add debug logging to Mutex creation (idempotent)
# ────────────────────────────────────────────────────────────
PHYSFS_POSIX_C="${TOPDIR}/physfs-src/src/physfs_platform_posix.c"

if ! grep -q "PHYSFS_SWITCH_MUTEX_DEBUG" "$PHYSFS_POSIX_C"; then
    echo ">>> Adding debug logging to Mutex creation..."
    
    # Patch __PHYSFS_platformCreateMutex to log errors
    sed -i '/^void \*__PHYSFS_platformCreateMutex(void)$/,/^{$/ {
        /^{$/a\
/* PHYSFS_SWITCH_MUTEX_DEBUG */\
#ifdef __SWITCH__\
    printf("Mutex: creating...\\n"); fflush(stdout);\
#endif
    }' "$PHYSFS_POSIX_C"

    sed -i 's/rc = pthread_mutex_init(&m->mutex, NULL);/\
    rc = pthread_mutex_init(\&m->mutex, NULL);\
#ifdef __SWITCH__\
    if (rc != 0) { printf("Mutex: pthread_mutex_init failed with rc=%d\\n", rc); fflush(stdout); }\
#endif/g' "$PHYSFS_POSIX_C"

    sed -i 's/rc = pthread_mutex_init(&m->mutex, NULL);/\
    rc = pthread_mutex_init(\&m->mutex, NULL);\
#ifdef __SWITCH__\
    if (rc != 0) { printf("Mutex: pthread_mutex_init failed with rc=%d\\n", rc); fflush(stdout); }\
#endif/g' "$PHYSFS_POSIX_C"

    # Patch __PHYSFS_platformCalcUserDir to return "./"
    sed -i '/^char \*__PHYSFS_platformCalcUserDir(void)$/,/^{$/ {
        /^{$/a\
/* PHYSFS_SWITCH_USERDIR_PATCH */\
#ifdef __SWITCH__\
    /* On Switch, return "./" to use current directory. */\
    char *switch_retval = (char *) allocator.Malloc(3);\
    if (switch_retval) strcpy(switch_retval, "./");\
    return switch_retval;\
#endif
    }' "$PHYSFS_POSIX_C"

else
    echo ">>> PhysFS mutex debug logging already added."
fi

# ────────────────────────────────────────────────────────────
# Fix up the debug logging (idempotent, also for already patched trees):
# - an earlier "platformInit FAILED" print matched the wrong "{" and landed
#   at the top of closeFileHandleList(), so it printed on every shutdown
# - trace prints only show with mkxp-z's debug switch (switch_trace_enabled,
#   see src/util/switch-trace.h); failure prints stay unconditional
# ────────────────────────────────────────────────────────────
python3 - "$PHYSFS_C" "$PHYSFS_POSIX_C" << 'PYTRACE'
import re, sys
MACRO = ("/* PHYSFS_SWITCH_TRACE_PATCH */\n#ifdef __SWITCH__\n#include <stdio.h>\n"
         "extern int switch_trace_enabled;\n"
         "#define PHYSFS_SWITCH_TRACE(...) \\\n"
         "    do { if (switch_trace_enabled) { printf(__VA_ARGS__); fflush(stdout); } } while (0)\n"
         "#endif\n")
for path in sys.argv[1:]:
    s = open(path).read()
    s = s.replace('#ifdef __SWITCH__\n        printf("PHYSFS_init: platformInit FAILED\\n"); '
                  'fflush(stdout);\n#endif\n', '')
    s = re.sub(r'printf\(("(?:PHYSFS_init|Mutex): (?![^"]*(?:FAILED|failed))[^;]*?)\); fflush\(stdout\);',
               r'PHYSFS_SWITCH_TRACE(\1);', s)
    s = re.sub(r'printf\(("(?:PHYSFS_init|Mutex): (?![^"]*(?:FAILED|failed))[^;]*?)\);\n(\s*)fflush\(stdout\);',
               r'PHYSFS_SWITCH_TRACE(\1);', s)
    if "PHYSFS_SWITCH_TRACE(" in s and "PHYSFS_SWITCH_TRACE_PATCH" not in s:
        s = MACRO + s
    open(path, 'w').write(s)
PYTRACE

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

# Build SDL_sound with reduced parallelism to avoid file truncation errors
# The modplug codec can cause race conditions when building in parallel with many jobs
# Limit to 4 jobs max to avoid file corruption during library creation
echo "  Building SDL_sound (this may take a few minutes)..."
NPROC_COUNT=$(nproc)
if [ "$NPROC_COUNT" -gt 4 ]; then
    PARALLEL_JOBS=4
else
    PARALLEL_JOBS=$NPROC_COUNT
fi
make -C "${TOPDIR}/SDL_sound-build" -j${PARALLEL_JOBS}

make -C "${TOPDIR}/SDL_sound-build" install

# ────────────────────────────────────────────────────────────
# 3. Build FluidSynth (MIDI playback, linked statically into mkxp-z)
# ────────────────────────────────────────────────────────────
# FluidSynth >= 2.4 can use C++11 threads instead of glib (osal=cpp11).
# Only the library is built; mkxp-z renders the synth itself, so every
# audio/MIDI driver and optional dependency is off.
echo ">>> Building FluidSynth for Switch..."
FLUIDSYNTH_VERSION=v2.5.7
FLUID_SRC="${LIBS_DIR}/fluidsynth-src"
FLUID_BUILD="${LIBS_DIR}/fluidsynth-build"
FLUID_PREFIX="${LIBS_DIR}/fluidsynth-switch"
if [ ! -d "${FLUID_SRC}" ]; then
    git clone --depth 1 --branch "${FLUIDSYNTH_VERSION}" https://github.com/FluidSynth/fluidsynth.git "${FLUID_SRC}"
fi

FLUID_OFF=""
for opt in alsa aufile dbus ipv6 jack ladspa libinstpatch libsndfile midishare network \
           oss dsound wasapi waveout winmidi sdl3 pulseaudio pipewire readline openmp \
           unicode systemd portaudio native-dls; do
    FLUID_OFF="${FLUID_OFF} -Denable-${opt}=OFF"
done

# fluidsynth_switch_compat.h stubs pthread_setschedparam (missing in newlib)
#
# FluidSynth must be built with -fPIE, not -fPIC: devkitA64's -mtp=soft TLS
# codegen is broken in PIC mode (GCC emits `lsl tp, #1` instead of `tp+off`),
# so the thread_local in fluid_sys_cpp11.cpp would fault on synth teardown
# (2168-0002 0x4A8 in fluid_private_free). -fPIE produces correct code and is
# what mkxp-z itself uses.
FLUID_CFLAGS="${CFLAGS//-fPIC/-fPIE}"
FLUID_CXXFLAGS="${CXXFLAGS//-fPIC/-fPIE}"
cmake -S "${FLUID_SRC}" -B "${FLUID_BUILD}" \
    -DCMAKE_SYSTEM_NAME=Generic \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=${DEVKITARM}/bin/aarch64-none-elf-gcc \
    -DCMAKE_CXX_COMPILER=${DEVKITARM}/bin/aarch64-none-elf-g++ \
    -DCMAKE_AR=${DEVKITARM}/bin/aarch64-none-elf-gcc-ar \
    -DCMAKE_RANLIB=${DEVKITARM}/bin/aarch64-none-elf-gcc-ranlib \
    -DCMAKE_FIND_ROOT_PATH=${DEVKITPRO}/portlibs/switch \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -Dosal=cpp11 \
    -Denable-threads=ON \
    ${FLUID_OFF} \
    -DCMAKE_INSTALL_PREFIX="${FLUID_PREFIX}" \
    -DCMAKE_C_FLAGS="${FLUID_CFLAGS} -include ${TOPDIR}/switch/deps/fluidsynth_switch_compat.h" \
    -DCMAKE_CXX_FLAGS="${FLUID_CXXFLAGS}"

make -C "${FLUID_BUILD}" -j"$(nproc)" libfluidsynth

# Install the library, headers and pkg-config file (make install would also
# link the fluidsynth command-line player, which is not needed)
rm -rf "${FLUID_PREFIX}"
mkdir -p "${FLUID_PREFIX}/lib/pkgconfig" "${FLUID_PREFIX}/include/fluidsynth"
cp "${FLUID_BUILD}/src/libfluidsynth.a" "${FLUID_PREFIX}/lib/"
cp "${FLUID_BUILD}/fluidsynth.pc" "${FLUID_PREFIX}/lib/pkgconfig/"
cp "${FLUID_BUILD}/include/fluidsynth.h" "${FLUID_PREFIX}/include/"
cp "${FLUID_SRC}"/include/fluidsynth/*.h "${FLUID_BUILD}/include/fluidsynth/version.h" \
   "${FLUID_PREFIX}/include/fluidsynth/"

# ────────────────────────────────────────────────────────────
# 4. Build Pixman (software rasterizer; rebuilt to fix soft-TLS codegen)
# ────────────────────────────────────────────────────────────
# devkitPro's prebuilt libpixman-1.a was compiled with -fPIC but without
# -ftls-model=local-exec. devkitA64 then miscompiles thread-local accesses as
# `lsl tp, #1` instead of `tp + offset`; the linked binary had 11 such sites in
# _pixman_implementation_lookup_composite. mkxp-z only uses pixman's region
# functions today, but shipping broken TLS code is a latent data-abort. Rebuild
# 0.42.2 from source with the same -fPIE policy as mkxp-z and FluidSynth.
echo ">>> Building Pixman for Switch..."
PIXMAN_VERSION=0.42.2
PIXMAN_SHA256=ea1480efada2fd948bc75366f7c349e1c96d3297d09a3fe62626e38e234a625e
PIXMAN_TARBALL=/tmp/pixman-${PIXMAN_VERSION}.tar.gz
PIXMAN_SRC="${LIBS_DIR}/pixman-src"
PIXMAN_BUILD="${LIBS_DIR}/pixman-build"
PIXMAN_PREFIX="${LIBS_DIR}/pixman-switch"
if [ ! -f "${PIXMAN_SRC}/meson.build" ]; then
    curl -fL --retry 3 -o "${PIXMAN_TARBALL}" \
        "https://cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz"
    echo "${PIXMAN_SHA256}  ${PIXMAN_TARBALL}" | sha256sum -c -
    rm -rf "${PIXMAN_SRC}"
    mkdir -p "${PIXMAN_SRC}"
    tar xf "${PIXMAN_TARBALL}" -C "${PIXMAN_SRC}" --strip-components=1
fi
rm -rf "${PIXMAN_BUILD}" "${PIXMAN_PREFIX}"
/opt/devkitpro/meson-toolchain.sh switch > /tmp/pixman-cross.txt
sed -i 's/-fPIC/-fPIE/g' /tmp/pixman-cross.txt
meson setup "${PIXMAN_BUILD}" "${PIXMAN_SRC}" \
    --cross-file=/tmp/pixman-cross.txt \
    --buildtype=release \
    --default-library=static \
    --prefix="${PIXMAN_PREFIX}" \
    --libdir=lib \
    -Dtests=disabled \
    -Dgtk=disabled \
    -Dopenmp=disabled \
    -Dlibpng=disabled
ninja -C "${PIXMAN_BUILD}"
ninja -C "${PIXMAN_BUILD}" install

echo
echo "✅ Dependency build complete!"
echo "→ PhysicsFS:  ${LIBS_DIR}/physfs-switch/lib/libphysfs.a"
echo "→ SDL_sound:  ${LIBS_DIR}/SDL_sound-switch/lib/libSDL2_sound.a"
echo "→ FluidSynth: ${FLUID_PREFIX}/lib/libfluidsynth.a"
echo "→ Pixman:     ${PIXMAN_PREFIX}/lib/libpixman-1.a"