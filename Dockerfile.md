# Image with the ClownMDSDK toolchain for building ToyGine2 targeting Sega Mega Drive/Genesis
# (m68k-elf).
#
# The SDK ships no binaries, so the toolchain is built from source in four stages:
#   stage1  GNU Binutils  (assembler/linker for m68k-elf)
#   stage2  GCC           (C/C++ cross-compiler for m68k-elf; the longest one)
#   stage3  AS            (Alfred Arnold's Z80 macro assembler; asl-releases submodule)
#   stage4  misc          (headers, cartridge.mk/generic.mk, cartridge.ld, ClownLZSS)
#
# It lands in /opt/clownmdsdk, which the final stage copies out of the builder.
#
# A parallel stage builds BlastEm from a pinned Mercurial changeset into /opt/blastem, for
# running Mega Drive ROMs headless in CI (`blastem -t -b <frames> rom.bin`).
#
# Usage (same as the other toygine2 images):
#   docker build -t toygine2-md - < Dockerfile.md
#   docker run --rm -v "$PWD":/workspace -w /workspace toygine2-md \
#       make -C path/to/project

# Pinned toolchain versions. Global ARGs so the final image can expose them as labels;
# CLOWNMDSDK_COMMIT and BLASTEM_COMMIT are bumped like dependencies by the update workflows.
ARG CLOWNMDSDK_COMMIT=7bc06af715c86956dbac37252eb67033740bcc0f
ARG GCC_VERSION=16.2.0
ARG BLASTEM_COMMIT=515a32bc605d11144db7bef9e0ea0538505eee48

# --- Stage 1: ClownMDSDK toolchain builder ---
FROM debian:trixie-slim AS toolchain-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# build-essential/flex/bison and libgmp/mpfr/mpc/zstd-dev build binutils and gcc; cmake builds
# AS (stage3) and ClownLZSS (stage4); xz-utils unpacks the source archives. texinfo is absent on
# purpose: MAKEINFO=true below skips the info manuals nobody reads here.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential cmake git curl ca-certificates patch flex bison \
    libgmp-dev libmpfr-dev libmpc-dev libzstd-dev xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Pinned for reproducibility, bumped like a dependency.
ARG BINUTILS_VERSION=2.47

# From the global ARGs above.
ARG CLOWNMDSDK_COMMIT
ARG GCC_VERSION

# Archive sha256 (empty = check skipped; fill in when pinning versions).
ARG BINUTILS_SHA256=
ARG GCC_SHA256=

# 1 = skip building example/ for the smoke test after install.
ARG SKIP_SMOKE_TEST=0

ENV CLOWNMDSDK=/opt/clownmdsdk
ENV PATH="${CLOWNMDSDK}/bin:${PATH}"

# Step 0: Git clone and checkout.
RUN mkdir -p /tmp/clownmdsdk \
    && cd /tmp/clownmdsdk \
    && git init -q \
    && git remote add origin https://github.com/Clownacy/clownmdsdk.git \
    && git fetch --depth 1 origin "${CLOWNMDSDK_COMMIT}" \
    && git checkout -q --detach FETCH_HEAD \
    && git submodule update --init --recursive --depth 1

# Step 1: GNU Binutils (assembler/linker for m68k-elf).
# MAKEFLAGS carries -j and MAKEINFO into the plain make inside binutils.sh, which sets neither.
RUN cd /tmp/clownmdsdk/stage1 \
    && MAKEFLAGS="-j$(nproc) MAKEINFO=true" && export MAKEFLAGS \
    && curl -fSL --retry 3 -o binutils.tar.xz \
    "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" \
    && { [ -z "${BINUTILS_SHA256}" ] || echo "${BINUTILS_SHA256}  binutils.tar.xz" | sha256sum -c -; } \
    && tar -xf binutils.tar.xz \
    && bash ./binutils.sh \
    && rm -rf binutils.tar.xz "binutils-${BINUTILS_VERSION}" build-binutils

# Step 2: GCC (C/C++ cross-compiler for m68k-elf), the longest step.
RUN cd /tmp/clownmdsdk/stage2 \
    && MAKEFLAGS="-j$(nproc) MAKEINFO=true" && export MAKEFLAGS \
    && curl -fSL --retry 3 -o gcc.tar.xz \
    "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" \
    && { [ -z "${GCC_SHA256}" ] || echo "${GCC_SHA256}  gcc.tar.xz" | sha256sum -c -; } \
    && tar -xf gcc.tar.xz \
    && bash ./gcc.sh \
    && rm -rf gcc.tar.xz "gcc-${GCC_VERSION}" build-gcc

# Step 3: AS, the Z80 macro assembler (GNU Binutils cannot assemble Z80).
RUN cd /tmp/clownmdsdk/stage3 && bash ./as.sh "$(nproc)"

# Step 4: headers, makefile scripts, linker script, ClownLZSS.
RUN cd /tmp/clownmdsdk/stage4 \
    && bash ./misc.sh "$(nproc)"

# Smoke test: build the template cartridge with the freshly built toolchain.
RUN if [ "${SKIP_SMOKE_TEST}" != "1" ]; then \
    make -C /tmp/clownmdsdk/example/template-cartridge -j"$(nproc)" \
    && "${CLOWNMDSDK}/bin/m68k-elf-g++" --version; \
    fi

# --- Stage 2: BlastEm builder ---
FROM debian:trixie-slim AS blastem-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# mercurial: upstream is a Mercurial repo with no git mirror; python3: cpu_dsl.py generates the
# CPU cores at build time; libsdl2-dev/libgles-dev: BlastEm always links a renderer, even in
# headless mode. USE_FBDEV and NOGL do not compile upstream, and desktop OpenGL pulls Mesa DRI
# and LLVM (~155 MB) into the final image through libgl1, so the renderer is SDL2 with GLES.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential ca-certificates libgles-dev libsdl2-dev mercurial pkg-config python3 \
    && rm -rf /var/lib/apt/lists/*

# From the global ARG above.
ARG BLASTEM_COMMIT

# 1 = skip the headless ROM run after the build.
ARG SKIP_SMOKE_TEST=0

# Step 0: Mercurial clone; `-r` with the full node id makes hg verify the changeset hash.
RUN hg clone -q -r "${BLASTEM_COMMIT}" https://www.retrodev.com/repos/blastem /tmp/blastem

# Step 1: build and install next to the data files. BlastEm resolves rom.db and the default
# configs from its own executable directory, so they must share /opt/blastem. NONUKLEAR drops
# the GUI menu headless mode never shows. x86_64 gets the dynarec cores; arm64 falls back to
# the interpreter cores upstream calls NEW_CORE.
# The link recipe is not marked recursive, so make closes its jobserver fds while MAKEFLAGS
# still advertises them, and GCC's lto-wrapper dies with "write jobserver: Bad file descriptor"
# (seen on amd64). CC drops MAKEFLAGS; OPT restates upstream's -O2 with an LTRANS job count.
RUN cd /tmp/blastem \
    && make -j"$(nproc)" CC="env -u MAKEFLAGS cc" OPT="-O2 -flto=$(nproc)" \
    USE_GLES=1 NONUKLEAR=1 blastem \
    && mkdir -p /opt/blastem \
    && cp blastem rom.db default.cfg systems.cfg /opt/blastem/ \
    && rm -rf /tmp/blastem

# Copied after the build, so a ClownMDSDK bump reruns the smoke test and leaves the compile cached.
COPY --from=toolchain-builder /tmp/clownmdsdk/example/template-cartridge /tmp/template-cartridge

# Smoke test: run the template cartridge headless. -t stops BlastEm spawning a terminal
# emulator and blocking on its FIFOs when stdout is not a TTY, as in CI.
RUN if [ "${SKIP_SMOKE_TEST}" != "1" ]; then \
    /opt/blastem/blastem -v \
    && /opt/blastem/blastem -t -b 60 /tmp/template-cartridge/bin/template-cartridge.bin; \
    fi

# --- Stage 3: final image ---
FROM debian:trixie-slim

# make: Makefile projects (cartridge.mk/generic.mk); cmake: toolchain.cmake; ninja-build: the
# consumer CMake presets use the Ninja generator; git and ca-certificates: actions/checkout runs
# git from the image itself, and without it checkout silently falls back to the REST API tarball,
# where 'submodules: recursive' becomes a hard error; curl/xz-utils/unzip: CI steps fetch and
# unpack tools inside the job container; libgmp10/libmpfr6/libmpc3/libzstd1: shared libs the
# host m68k-elf-g++ executable links against (a cross-compiler, but it runs on the host);
# libsdl2-2.0-0/libgles2: BlastEm links them even when run headless.
#
# trixie/main carries cmake 3.31.6 against toygine2's >= 3.27, so no extra suite is needed and
# the builder stage takes the same package. ClownLZSS, built there, declares
# cmake_minimum_required(VERSION 3.7.2): below the 3.10 deprecation line, so cmake warns, and
# above the 3.5 floor CMake 4 removed, so a CMake 4 base would still build it.
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    make cmake ninja-build git ca-certificates curl xz-utils unzip \
    libgmp10 libmpfr6 libmpc3 libzstd1 libgles2 libsdl2-2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=toolchain-builder /opt/clownmdsdk /opt/clownmdsdk
COPY --from=blastem-builder /opt/blastem /opt/blastem

ENV LANG=C.UTF-8
ENV CLOWNMDSDK=/opt/clownmdsdk
ENV PATH="${CLOWNMDSDK}/bin:/opt/blastem:${PATH}"

WORKDIR /workspace
CMD ["bash"]

LABEL org.opencontainers.image.authors="Toyman Interactive <https://github.com/ToymanInteractive>"
LABEL org.opencontainers.image.url="https://github.com/ToymanInteractive/toygine2-images"
LABEL org.opencontainers.image.documentation="https://github.com/ToymanInteractive/toygine2-images/blob/main/README.md"
LABEL org.opencontainers.image.source="https://github.com/ToymanInteractive/toygine2-images"

LABEL org.opencontainers.image.vendor="Toyman Interactive"
LABEL org.opencontainers.image.licenses="MIT"

LABEL org.opencontainers.image.title="ToyGine2 Mega Drive/Genesis Toolchain"
LABEL org.opencontainers.image.description="ClownMDSDK toolchain for building ToyGine2 targeting Sega Mega Drive/Genesis."
LABEL org.opencontainers.image.base.name="docker.io/library/debian:trixie-slim"

LABEL com.toygine2.console="Sega Mega Drive/Genesis"
LABEL com.toygine2.toolchain="ClownMDSDK"

# Re-declared here so the labels below can read them.
ARG CLOWNMDSDK_COMMIT
ARG GCC_VERSION
ARG BLASTEM_COMMIT
LABEL com.toygine2.sdk.clownmdsdk.commit="${CLOWNMDSDK_COMMIT}"
LABEL com.toygine2.sdk.gcc.version="${GCC_VERSION}"
LABEL com.toygine2.sdk.blastem.commit="${BLASTEM_COMMIT}"
