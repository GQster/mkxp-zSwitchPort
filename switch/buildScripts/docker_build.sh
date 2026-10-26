#!/bin/bash
# Run Switch build steps in the switch-dev container as the calling user, so
# build outputs in the repo are owned by you rather than root.
#
#   switch/buildScripts/docker_build.sh [deps|ruby|mkxpz|all|shell]
#
#   deps   PhysicsFS + SDL_sound (configure_mkxpz.sh)
#   ruby   Ruby static library (build_ruby_switch.sh); RUBY_CLEAN=1 rebuilds
#          from a fresh source tree
#   mkxpz  mkxp-z.nro (build_mkxpz_switch.sh), the default
#   all    deps, ruby, then mkxpz
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
    docker run --rm $TTY --user "$(id -u):$(id -g)" -e HOME=/tmp -e RUBY_CLEAN \
        -v "$ROOT":/workspace -w /workspace "$IMAGE" "$@"
}

case "${1:-mkxpz}" in
    deps)  run bash switch/buildScripts/configure_mkxpz.sh ;;
    ruby)  run bash switch/buildScripts/build_ruby_switch.sh ;;
    mkxpz) run bash switch/buildScripts/build_mkxpz_switch.sh ;;
    all)   run bash -c "bash switch/buildScripts/configure_mkxpz.sh &&
                        bash switch/buildScripts/build_ruby_switch.sh &&
                        bash switch/buildScripts/build_mkxpz_switch.sh" ;;
    shell) TTY=-it; run bash ;;
    *)
        sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
