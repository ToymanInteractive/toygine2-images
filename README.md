# ToyGine2 Images

Docker images for toygine2 CI/CD pipelines, automatically rebuilt when upstream dependencies are updated. Images are published to [GitHub Container Registry](https://github.com/orgs/ToymanInteractive/packages).

## Images

| Image                      | Description                                                                                                                             |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| toygine2.genesis.toolchain | [ClownMDSDK](https://github.com/Clownacy/clownmdsdk) toolchain for building ToyGine2 targeting the Sega Mega Drive/Genesis (`m68k-elf`) |

### Genesis (Sega Mega Drive/Genesis)

`Dockerfile.genesis` ships a ready-to-use [ClownMDSDK](https://github.com/Clownacy/clownmdsdk) toolchain for building ToyGine2 targeting the Sega Mega Drive/Genesis (`m68k-elf`).

The toolchain is installed into `/opt/clownmdsdk`.

Run (build a Makefile project mounted from the host):

```sh
docker run --rm -v "$PWD":/workspace -w /workspace toygine2-genesis \
    make -C path/to/project
```
