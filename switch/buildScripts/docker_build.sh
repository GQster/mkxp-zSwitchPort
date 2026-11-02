#!/bin/bash
# Run Switch build steps in the switch-dev container as the calling user, so
# build outputs in the repo are owned by you rather than root.
#
#   switch/buildScripts/docker_build.sh [deps|mkxpz|all|shell]
#
#   deps   PhysicsFS + SDL_sound (configure_mkxpz.sh)
#   mkxpz  mkxp-z.nro (build_mkxpz_switch.sh, which also builds Ruby from
#          subprojects/ruby-3.1.wrap), the default
#   all    deps, then mkxpz
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
    deps)  run bash switch/buildScripts/configure_mkxpz.sh ;;
    mkxpz) run bash switch/buildScripts/build_mkxpz_switch.sh ;;
    all)   run bash -c "bash switch/buildScripts/configure_mkxpz.sh &&
                        bash switch/buildScripts/build_mkxpz_switch.sh" ;;
    shell) TTY=-it; run bash ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
