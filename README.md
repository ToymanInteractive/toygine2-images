# ToyGine2 Images

Docker images for toygine2 CI/CD pipelines, automatically rebuilt when upstream dependencies are updated. Images are published to [GitHub Container Registry](https://github.com/orgs/ToymanInteractive/packages).

## Images

| Image                 | Description                                                                                                                             |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| toygine2.md.toolchain | [ClownMDSDK](https://github.com/Clownacy/clownmdsdk) toolchain for building ToyGine2 targeting the Sega Mega Drive/Genesis (`m68k-elf`) |

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
