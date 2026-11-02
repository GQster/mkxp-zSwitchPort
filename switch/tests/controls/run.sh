#!/bin/bash
# Builds and runs the controller-profile tests on the host (needs g++ and
# SDL2 development headers, e.g. libsdl2-dev).
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=$(mktemp -d)
g++ -std=c++14 -Wall -I"$ROOT/switch" -I"$ROOT/src" $(sdl2-config --cflags) \
    "$ROOT/switch/tests/controls/test_controls.cpp" "$ROOT/switch/switch_controls.cpp" \
    $(sdl2-config --libs) -o "$OUT/test_controls"
"$OUT/test_controls"
rm -rf "$OUT"
