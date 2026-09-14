# Image with the ClownMDSDK toolchain for building ToyGine2 targeting Sega Mega Drive/Genesis
# (m68k-elf).
#
# The SDK ships no binaries, so the toolchain is built from source in four stages:
#   stage1  GNU Binutils  (assembler/linker for m68k-elf)
#   stage2  GCC           (C/C++ cross-compiler for m68k-elf; the longest one)
#   stage3  AS            (Alfred Arnold's Z80 macro assembler; asl-releases submodule)
#   stage4  misc          (headers, cartridge.mk/generic.mk, cartridge.ld, ClownLZSS)
#
# The toolchain is installed into /opt/clownmdsdk and copied into the final image
# by the runtime stage.
#
# A parallel stage builds the BlastEm emulator from a pinned Mercurial changeset into /opt/blastem,
# for running Mega Drive ROMs headless (`blastem -t -b <frames> rom.bin`) in CI.
#
# Usage (same as the other toygine2 images):
#   docker build -t toygine2-md - < Dockerfile.md
#   docker run --rm -v "$PWD":/workspace -w /workspace toygine2-md \
#       make -C path/to/project

# Pinned toolchain versions (global ARGs so the final image can expose them as metadata labels;
# CLOWNMDSDK_COMMIT and BLASTEM_COMMIT are bumped like dependencies by the update workflows).
ARG CLOWNMDSDK_COMMIT=7bc06af715c86956dbac37252eb67033740bcc0f
ARG GCC_VERSION=16.2.0
ARG BLASTEM_COMMIT=515a32bc605d11144db7bef9e0ea0538505eee48

# --- Stage 1: ClownMDSDK toolchain builder ---
FROM debian:bookworm-slim AS toolchain-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# build-essential/texinfo/flex/bison and libgmp/mpfr/mpc/zstd-dev build binutils and gcc;
# cmake builds AS (stage3) and ClownLZSS (stage4); xz-utils unpacks the source archives.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential cmake git curl ca-certificates patch texinfo flex bison \
    libgmp-dev libmpfr-dev libmpc-dev libzstd-dev xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Versions are pinned for reproducibility (bumped like dependencies).
ARG BINUTILS_VERSION=2.47

# Inherit the globally pinned toolchain versions declared above.
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
# MAKEFLAGS parallelizes the plain make inside binutils.sh (invoked without -j).
RUN cd /tmp/clownmdsdk/stage1 \
    && MAKEFLAGS="-j$(nproc)" && export MAKEFLAGS \
    && curl -fSL --retry 3 -o binutils.tar.xz \
    "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz" \
    && { [ -z "${BINUTILS_SHA256}" ] || echo "${BINUTILS_SHA256}  binutils.tar.xz" | sha256sum -c -; } \
    && tar -xf binutils.tar.xz \
    && bash ./binutils.sh \
    && rm -rf binutils.tar.xz "binutils-${BINUTILS_VERSION}" build-binutils

# Step 2: GCC (C/C++ cross-compiler for m68k-elf), the longest step.
RUN cd /tmp/clownmdsdk/stage2 \
    && MAKEFLAGS="-j$(nproc)" && export MAKEFLAGS \
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
FROM debian:bookworm-slim AS blastem-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# mercurial: upstream is a Mercurial repo with no git mirror; python3: cpu_dsl.py generates the
# CPU cores at build time; libsdl2-dev/libgles-dev: BlastEm always links a renderer, even though
# headless mode never opens a window. USE_FBDEV and NOGL do not compile upstream, and desktop
# OpenGL pulls Mesa DRI and LLVM (~155 MB) into the final image through libgl1, so the renderer
# is SDL2 with GLES.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential ca-certificates libgles-dev libsdl2-dev mercurial pkg-config python3 \
    && rm -rf /var/lib/apt/lists/*

# Inherit the globally pinned BLASTEM_COMMIT declared above.
ARG BLASTEM_COMMIT

# 1 = skip the headless ROM run after the build.
ARG SKIP_SMOKE_TEST=0

# Step 0: Mercurial clone; `-r` with the full node id makes hg verify the changeset hash.
RUN hg clone -q -r "${BLASTEM_COMMIT}" https://www.retrodev.com/repos/blastem /tmp/blastem

# Step 1: build and install next to the data files. BlastEm resolves rom.db and the default
# configs from its own executable directory, so they must share /opt/blastem. NONUKLEAR drops
# the GUI menu that headless mode never shows. x86_64 gets the dynarec cores; other CPUs (arm64)
# fall back to the interpreter cores upstream calls NEW_CORE.
# The link recipe is not marked recursive, so make closes its jobserver fds while MAKEFLAGS still
# advertises them; GCC's lto-wrapper then dies with "write jobserver: Bad file descriptor" (seen
# on amd64). CC drops MAKEFLAGS and OPT restates upstream's -O2 with an explicit LTRANS job count.
RUN cd /tmp/blastem \
    && make -j"$(nproc)" CC="env -u MAKEFLAGS cc" OPT="-O2 -flto=$(nproc)" \
    USE_GLES=1 NONUKLEAR=1 blastem \
    && mkdir -p /opt/blastem \
    && cp blastem rom.db default.cfg systems.cfg /opt/blastem/ \
    && rm -rf /tmp/blastem

# Copied after the build, so a ClownMDSDK bump reruns only the smoke test and the compile stays
# cached.
COPY --from=toolchain-builder /tmp/clownmdsdk/example/template-cartridge /tmp/template-cartridge

# Smoke test: run the template cartridge headless. -t keeps BlastEm from spawning a terminal
# emulator (and blocking on its FIFOs) when stdout is not a TTY, as in CI.
RUN if [ "${SKIP_SMOKE_TEST}" != "1" ]; then \
    /opt/blastem/blastem -v \
    && /opt/blastem/blastem -t -b 60 /tmp/template-cartridge/bin/template-cartridge.bin; \
    fi

# --- Stage 3: final image ---
FROM debian:bookworm-slim

# make: Makefile projects (cartridge.mk/generic.mk); cmake: toolchain.cmake; ninja-build: the
# consumer CMake presets use the Ninja generator; git and ca-certificates: actions/checkout runs
# git from the image itself, and without it checkout silently falls back to the REST API tarball,
# where 'submodules: recursive' becomes a hard error; curl/xz-utils/unzip: CI steps fetch and
# unpack tools inside the job container; libgmp10/libmpfr6/libmpc3/libzstd1: shared libs the
# host m68k-elf-g++ executable links against (a cross-compiler, but it runs on the host);
# libsdl2-2.0-0/libgles2: BlastEm links them even when run headless.
#
# cmake comes from bookworm-backports: bookworm/main ships 3.25.1 and toygine2 requires >= 3.27.
# The builder stage keeps the older main cmake on purpose: newer CMake rejects the old
# cmake_minimum_required of the AS and ClownLZSS sources built there.
ARG DEBIAN_FRONTEND=noninteractive
RUN echo "deb http://deb.debian.org/debian bookworm-backports main" \
    > /etc/apt/sources.list.d/bookworm-backports.list \
    && apt-get update -qq && apt-get install -y --no-install-recommends \
    make ninja-build git ca-certificates curl xz-utils unzip \
    libgmp10 libmpfr6 libmpc3 libzstd1 libgles2 libsdl2-2.0-0 \
    && apt-get install -y --no-install-recommends -t bookworm-backports cmake \
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
LABEL org.opencontainers.image.base.name="docker.io/library/debian:bookworm-slim"

LABEL com.toygine2.console="Sega Mega Drive/Genesis"
LABEL com.toygine2.toolchain="ClownMDSDK"

# Re-declare to bring the globally pinned values into this stage for the labels below.
ARG CLOWNMDSDK_COMMIT
ARG GCC_VERSION
ARG BLASTEM_COMMIT
LABEL com.toygine2.sdk.clownmdsdk.commit="${CLOWNMDSDK_COMMIT}"
LABEL com.toygine2.sdk.gcc.version="${GCC_VERSION}"
LABEL com.toygine2.sdk.blastem.commit="${BLASTEM_COMMIT}"
