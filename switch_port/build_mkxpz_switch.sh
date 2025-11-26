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
rm -rf "${BUILD}"
fi

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
  -Dbuild_tests=false \
  -Denable-https=false

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
echo "Next steps:"
echo "  1. Convert to .nro:  elf2nro ${BUILD}/mkxp-z ${BUILD}/mkxp-z.nro"
echo "  2. Copy to SD card:  /switch/mkxp-z/"
echo "  3. Add game assets:  /switch/mkxp-z/Game.rgssad"
echo ""
echo "════════════════════════════════════════════════════════════"