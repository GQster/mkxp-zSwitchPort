#!/bin/bash
set -e

cd /workspace/switch/tests/helloWorld

echo "[1/4] Compiling hello.elf"
aarch64-none-elf-gcc -fPIE hello.c \
    -specs=/opt/devkitpro/libnx/switch.specs \
    -march=armv8-a -mtune=cortex-a57 -mtp=soft \
    -I/opt/devkitpro/libnx/include \
    -L/opt/devkitpro/libnx/lib \
    -Wl,-z,notext \
    -lnx \
    -o hello.elf 2>&1 && echo "Compile OK" || { echo "Compile FAILED"; exit 1; }

echo "[2/4] Creating hello.nacp"
# Simple NACP: title, author, version
nacptool --create "Hello World (mkxp-z test)" "grant" "0.1.0" hello.nacp

echo "[3/4] Converting to hello.nro with NACP"
elf2nro hello.elf hello.nro --nacp=hello.nacp 2>&1 && echo "NRO OK" || { echo "NRO FAILED"; exit 1; }

echo "[4/4] Inspecting relocations"
aarch64-none-elf-readelf -d hello.elf | grep -iE 'REL|RELR|RELA' || true
aarch64-none-elf-readelf -r hello.elf | wc -l

echo
echo "Result:"
ls -la hello.elf hello.nacp hello.nro