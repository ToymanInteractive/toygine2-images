# ToyGine2 Images

Docker images for toygine2 CI/CD pipelines, automatically rebuilt when upstream dependencies are updated. Images are published to [GitHub Container Registry](https://github.com/orgs/ToymanInteractive/packages).

## Images

| Image                    | Description                                                                                                                             |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| toygine2.gba.toolchain   | [devkitARM](https://devkitpro.org/wiki/Getting_Started) toolchain for building ToyGine2 targeting the Nintendo Game Boy Advance         |
| toygine2.md.toolchain    | [ClownMDSDK](https://github.com/Clownacy/clownmdsdk) toolchain for building ToyGine2 targeting the Sega Mega Drive/Genesis (`m68k-elf`) |
| toygine2.n64.toolchain   | [Libdragon](https://github.com/DragonMinded/libdragon) toolchain for building ToyGine2 targeting the Nintendo 64 (`mips64-elf`)         |
| toygine2.gcc.toolchain   | [GCC](https://gcc.gnu.org/) built from the latest release for building and testing ToyGine2 on Linux                                    |
| toygine2.clang.toolchain | [Clang](https://clang.llvm.org/) with libc++ from the latest LLVM release for building and testing ToyGine2 on Linux                    |

Every image has `python3` for the helper scripts toygine2 CI runs inside the container. The devkitPro images get it from their upstream base, and the Debian-based ones install it.

### GBA (Nintendo Game Boy Advance)

`Dockerfile.gba` extends the upstream [devkitARM](https://devkitpro.org/wiki/Getting_Started) image for building ToyGine2 targeting the Nintendo Game Boy Advance.

The toolchain is installed into `/opt/devkitpro/devkitARM`, and `DEVKITPRO` and `DEVKITARM` are set.

Run (build a Makefile project mounted from the host):

```sh
docker run --rm -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.gba.toolchain:latest \
    make -C path/to/project
```

The image also includes a headless [mGBA](https://mgba.io/) build for running ROMs in CI. `mgba-headless` is installed in `/usr/local/bin`, which is already on `PATH`.

The [emibios](https://github.com/coolbho3k/emibios) GBA BIOS replacement is installed as `/usr/local/share/emibios/gba_bios.bin`. Unlike the retail BIOS, it can be redistributed (LGPL-3.0-or-later). Pass it with `-b`. mGBA logs `BIOS checksum incorrect` because it compares against the retail BIOS; emulation still runs normally:

```sh
docker run --rm -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.gba.toolchain:latest \
    mgba-headless -b /usr/local/share/emibios/gba_bios.bin build/rom.gba
```

### Genesis (Sega Mega Drive/Genesis)

`Dockerfile.md` builds the [ClownMDSDK](https://github.com/Clownacy/clownmdsdk) toolchain for building ToyGine2 targeting the Sega Mega Drive/Genesis (`m68k-elf`).

The toolchain is installed into `/opt/clownmdsdk`.

Run (build a Makefile project mounted from the host):

```sh
docker run --rm -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.md.toolchain:latest \
    make -C path/to/project
```

The image also includes the [BlastEm](https://www.retrodev.com/blastem/) emulator for running ROMs headless in CI. It is installed in `/opt/blastem` and added to `PATH`. `-b <frames>` runs that many frames without a window and exits with status 0. Messages the ROM writes to the Gens KMod debug register are printed to stdout as `KDEBUG MESSAGE: ...`. Pass `-t` whenever stdout is not a terminal, otherwise BlastEm tries to open a terminal emulator for its debugger and hangs:

```sh
docker run --rm -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.md.toolchain:latest \
    blastem -t -b 600 build/rom.bin
```

### Nintendo 64

`Dockerfile.n64` builds the [Libdragon](https://github.com/DragonMinded/libdragon) toolchain for building ToyGine2 targeting the Nintendo 64 (`mips64-elf`). The image contains binutils, GCC, newlib, the libdragon library built from the `preview` branch, and its host tools (`n64tool`, `mksprite`, `audioconv64` and others).

Everything is installed into `/opt/libdragon`. The image sets `N64_INST` to this path, and libdragon's `n64.mk` uses that variable to find the toolchain.

The toolchain script and the library are pinned to separate commits. The script changes far less often than the library, and a shared pin would rebuild GCC on every library bump.

Run (build a Makefile project mounted from the host):

```sh
docker run --rm -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.n64.toolchain:latest \
    make -C path/to/project
```

The image ships no emulator yet, so ROMs are built in CI but not run.

### GCC (Linux host)

`Dockerfile.gcc` builds the latest [GCC](https://gcc.gnu.org/) release (C and C++ only) from source for building and testing ToyGine2 on Linux. Debian's own GCC is older, and Ubuntu 26.04 ships only a pre-release GCC 16 snapshot.

The compiler is installed into `/usr/local`, so `gcc`, `g++`, `c++` and a `cc` symlink are on `PATH`, and CMake and make find them without `CC` or `CXX`. Its `libstdc++` is registered with the dynamic loader, so test binaries run against it rather than Debian's older copy. The image also contains binutils, CMake, Ninja, make, git and Python 3.

The version and the tarball's sha256 are pinned in the Dockerfile. A weekly workflow checks for a new GCC release, verifies its GNU signature and opens a pull request with the new pin.

Run (configure, build and test a CMake project mounted from the host):

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.gcc.toolchain:latest \
    sh -c 'cmake --preset linux-release && cmake --build --preset linux-release && ctest --preset linux-release'
```

### Clang (Linux host)

`Dockerfile.clang` packages the latest [LLVM](https://llvm.org/) release for building and testing ToyGine2 on Linux with libc++. clang, libc++, libc++abi, libunwind and compiler-rt come from the official release archive. lld is rebuilt from the same release's sources, because the archive's lld needs ICU 70 from Ubuntu 22.04 and Debian ships ICU 76. The image has no GCC compiler and no libstdc++.

Everything is installed into `/usr/local`. Config files next to the compiler (`clang.cfg`, `clang++.cfg`) make libc++, lld, compiler-rt and libunwind the defaults, so `clang++ main.cpp` and a plain CMake configure need no extra flags. `cc` and `c++` point to `clang` and `clang++` and use the same defaults. The image has no libstdc++ headers, so `-stdlib=libstdc++` does not work here; use the GCC image for that. CMake picks `llvm-ar` and `llvm-ranlib` for Clang by itself.

The version and the checksums of the release archives and the source tarball are pinned in the Dockerfile. A weekly workflow takes them from the latest LLVM release and opens a pull request with the new pin.

Run (configure, build and test a CMake project mounted from the host):

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/workspace -w /workspace \
    ghcr.io/toymaninteractive/toygine2.clang.toolchain:latest \
    sh -c 'cmake --preset linux-release && cmake --build --preset linux-release && ctest --preset linux-release'
```
