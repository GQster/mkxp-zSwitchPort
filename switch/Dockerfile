# Personal local build environment for the Switch port (not part of the
# upstream branch), with the same
# packages the CI job (.github/workflows/autobuild.yml) installs:
#
#   docker build -t mkxp-z-switch switch
#   docker run --rm -it -u $(id -u):$(id -g) -e HOME=/tmp -v "$PWD":/src -w /src mkxp-z-switch
#
# The devkitPro image has devkitA64, libnx, switch-tools, SDL2 and OpenAL.
ARG BASE_IMAGE=devkitpro/devkita64:20251117
FROM ${BASE_IMAGE}

# Meson >= 1.4 from pip (Debian's is 1.0). Ruby (as baseruby) and bison are
# needed to build the Ruby subproject from its git tag tarball.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bison \
    g++ \
    libsdl2-dev \
    pkg-config \
    python3-pip \
    ruby \
 && pip3 install --break-system-packages meson==1.10.2 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
CMD ["/bin/bash"]
