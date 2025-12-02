#!/bin/bash
# check_pic.sh
# Scans static libraries and object files for absolute relocations in .rodata sections.

check_file() {
    local file="$1"
    # Extract .rodata relocation block.
    if [[ "$file" == *.a ]]; then
        output=$(aarch64-none-elf-objdump -r "$file" 2>/dev/null | sed -n '/RELOCATION RECORDS FOR \[.rodata\]/,/RELOCATION RECORDS FOR/p' | grep "R_AARCH64_ABS")
    else
        output=$(aarch64-none-elf-objdump -r "$file" 2>/dev/null | sed -n '/RELOCATION RECORDS FOR \[.rodata\]/,/RELOCATION RECORDS FOR/p' | grep "R_AARCH64_ABS")
    fi

    if [ ! -z "$output" ]; then
        echo "FOUND .rodata RELOCATIONS IN: $file"
        echo "$output" | head -n 5
        echo "..."
    fi
}

echo "Checking libraries for .rodata relocations..."

# Correct paths based on build script usage
LIBS=(
"/opt/devkitpro/portlibs/switch/lib/libEGL.a"
"/opt/devkitpro/portlibs/switch/lib/libGLESv2.a"
"/opt/devkitpro/portlibs/switch/lib/libharfbuzz.a"
"build-switch/switch/libswitch_stubs.a"
"/opt/devkitpro/libnx/lib/libnx.a"
"/opt/devkitpro/portlibs/switch/lib/libglapi.a"
"/workspace/libs/ruby-switch/lib/libruby-static.a"
"/workspace/libs/physfs-switch/lib/libphysfs.a"
"/opt/devkitpro/portlibs/switch/lib/libopenal.a"
"/opt/devkitpro/portlibs/switch/lib/libtheora.a"
"/opt/devkitpro/portlibs/switch/lib/libvorbisfile.a"
"/opt/devkitpro/portlibs/switch/lib/libvorbis.a"
"/opt/devkitpro/portlibs/switch/lib/libogg.a"
"/opt/devkitpro/portlibs/switch/lib/libSDL2.a"
"/workspace/libs/SDL_sound-switch/lib/libSDL2_sound.a"
"/opt/devkitpro/portlibs/switch/lib/libSDL2_ttf.a"
"/opt/devkitpro/portlibs/switch/lib/libfreetype.a"
"/opt/devkitpro/portlibs/switch/lib/libpixman-1.a"
"/opt/devkitpro/portlibs/switch/lib/libpng16.a"
"/opt/devkitpro/portlibs/switch/lib/libz.a"
"/opt/devkitpro/portlibs/switch/lib/libuchardet.a"
"/opt/devkitpro/portlibs/switch/lib/libSDL2_image.a"
"/opt/devkitpro/portlibs/switch/lib/libjpeg.a"
"/opt/devkitpro/portlibs/switch/lib/libwebp.a"
"/opt/devkitpro/portlibs/switch/lib/libbz2.a"
)

for lib in "${LIBS[@]}"; do
    if [ -f "$lib" ]; then
        check_file "$lib"
    else
        echo "Warning: $lib not found"
    fi
done

echo "Checking mkxp-z object files for .rodata relocations..."
find build-switch -name "*.o" | while read obj; do
    check_file "$obj"
done

echo "Done."
