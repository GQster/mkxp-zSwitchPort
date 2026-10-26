#!/bin/bash
set -e

# ══════════════════════════════════════════════════════════════
# 🎮 Nintendo Switch Build Script for mkxp-z
# ══════════════════════════════════════════════════════════════
BUILD_START_TIME=$(date +%s)

echo "════════════════════════════════════════════════════════════"
echo "  Building mkxp-z for Nintendo Switch (Homebrew)"
echo "════════════════════════════════════════════════════════════"

# ──────────────────────────────────────────────────────────────
# Setup devkitPro toolchain environment
# ──────────────────────────────────────────────────────────────
export DEVKITPRO=/opt/devkitpro
export DEVKITARM=${DEVKITPRO}/devkitA64
export PATH=${DEVKITARM}/bin:${DEVKITPRO}/tools/bin:$PATH

export ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD=${ROOT}/build-switch
LIBS=${ROOT}/libs
CROSS_FILE=${ROOT}/switch/switch.ini

# ──────────────────────────────────────────────────────────────
# CRITICAL: Force pkg-config to ONLY use Switch libraries
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
    rm -rf "${BUILD}" 2>/dev/null || echo "  ⚠️  Some files couldn't be removed, continuing..."
fi

# Switch sources live in the repo (switch/, src/switch_*.h, and the
# __SWITCH__ blocks in src/). This script used to regenerate or sed-patch
# them on every build; edit the files directly instead.

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

# ──────────────────────────────────────────────────────────────
# Generate .nacp and .nro
# ──────────────────────────────────────────────────────────────
if command -v nacptool > /dev/null 2>&1 && command -v elf2nro > /dev/null 2>&1; then
    echo "📦 Generating .nacp and .nro files..."
    
    # Create .nacp metadata file
    nacptool --create "mkxp-z" "mkxp-z Team" "1.0.0" "${BUILD}/mkxp-z.nacp"
    
    if [ -f "${BUILD}/mkxp-z.nacp" ]; then
        echo "  ✅ Generated: ${BUILD}/mkxp-z.nacp"
        
        # Stage RomFS: Switch files plus the shared Win32API preload
        rm -rf "${BUILD}/romfs"
        cp -r "${ROOT}/switch/romfs-root" "${BUILD}/romfs"
        cp "${ROOT}/scripts/preload/win32_wrap.rb" "${BUILD}/romfs/preload/"

        # Generate .nro with .nacp
        elf2nro "${BUILD}/mkxp-z" "${BUILD}/mkxp-z.nro" \
            --nacp="${BUILD}/mkxp-z.nacp" \
            --romfsdir="${BUILD}/romfs"
        if [ -f "${BUILD}/mkxp-z.nro" ]; then
            echo "  ✅ Generated: ${BUILD}/mkxp-z.nro"
        else
            echo "  ⚠️  Failed to generate .nro file"
        fi
    else
        echo "  ⚠️  Failed to generate .nacp file"
    fi
else
    echo "⚠️  nacptool or elf2nro not found, skipping .nro generation"
fi

# ──────────────────────────────────────────────────────────────
# Timing summary
# ──────────────────────────────────────────────────────────────
BUILD_END_TIME=$(date +%s)
ELAPSED=$((BUILD_END_TIME - BUILD_START_TIME))

ELAPSED_H=$((ELAPSED / 3600))
ELAPSED_M=$(((ELAPSED % 3600) / 60))
ELAPSED_S=$((ELAPSED % 60))

echo ""
echo "════════════════════════════════════════════════════════════"
printf " ⏱  Total build time: %02d:%02d:%02d\n" "$ELAPSED_H" "$ELAPSED_M" "$ELAPSED_S"

echo ""
echo "Next steps:"
echo "  1. Copy ${BUILD}/mkxp-z.nro to the SD card as /switch/mkxp-z/mkxp-z.nro"
echo "  2. Put each game in /switch/mkxp-z/Games/<Game Name>/ (with its Game.ini)"
echo ""
echo "════════════════════════════════════════════════════════════"