#!/bin/bash
# Run the Switch build in the switch-dev container as the calling user, so
# build outputs in the repo are owned by you rather than root.
#
#   switch/buildScripts/docker_build.sh [mkxpz|shell]
#
#   mkxpz  build-switch/mkxp-z.nro (build_mkxpz_switch.sh), the default
#   shell  interactive shell in the container
#
# The image is built from switch/buildScripts/dockerfile if it is missing.
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
IMAGE=${IMAGE:-switch-dev}
TTY=

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
    docker build -t "$IMAGE" "$ROOT/switch/buildScripts"
fi

run() {
    # HOME must be writable for tools that cache there (meson, python)
    docker run --rm $TTY --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$ROOT":/workspace -w /workspace "$IMAGE" "$@"
}

case "${1:-mkxpz}" in
    mkxpz) run bash switch/buildScripts/build_mkxpz_switch.sh ;;
    shell) TTY=-it; run bash ;;
    *)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
