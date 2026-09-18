# ToyGine2 Images

Docker images for toygine2 CI/CD pipelines, automatically rebuilt when upstream dependencies are updated. Images are published to [GitHub Container Registry](https://github.com/orgs/ToymanInteractive/packages).

## Images

| Image                  | Description                                                                                                                             |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| toygine2.gba.toolchain | [devkitARM](https://devkitpro.org/wiki/Getting_Started) toolchain for building ToyGine2 targeting the Nintendo Game Boy Advance         |
| toygine2.md.toolchain  | [ClownMDSDK](https://github.com/Clownacy/clownmdsdk) toolchain for building ToyGine2 targeting the Sega Mega Drive/Genesis (`m68k-elf`) |
| toygine2.n64.toolchain | [Libdragon](https://github.com/DragonMinded/libdragon) toolchain for building ToyGine2 targeting the Nintendo 64 (`mips64-elf`)         |

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
