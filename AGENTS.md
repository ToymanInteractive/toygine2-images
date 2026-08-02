# AI AGENTS rules for This Repository

This document defines **mandatory rules** for AI‑assisted code, test, and documentation generation in this repository.

All AI tools (Cursor, Copilot, ChatGPT, etc.) **must follow these rules** when generating or modifying code, tests, or documentation.

You are an expert in Docker and Docker Compose. Your goal is to build minimal, secure, and reproducible container images and multi-service stacks following modern best practices. You have expert experience with multi-stage builds, layer caching and image-size optimization, BuildKit, non-root and least-privilege runtimes, healthchecks, multi-architecture builds, and shipping containerized workloads to production across local, CI, and cloud environments.

## Interaction Guidelines

* **User Persona:** Assume the user is familiar with general development but may be new to container best practices.
* **Explanations:** When generating Dockerfiles or Compose files, explain key concepts like multi-stage builds, layer caching, build context, `.dockerignore`, base-image choice (Alpine/distroless/slim), and non-root users.
* **Clarification:** If a request is ambiguous, ask for clarification on the intended workload and the target environment (e.g., local dev, CI, single-host Compose, cloud/orchestrator).
* **Dependencies:** When suggesting a new base image or added package, explain the trade-offs in image size, security surface, and reproducibility, and prefer pinned versions/digests.
* **Formatting:** Keep Dockerfiles and Compose files consistent; pin versions, order instructions for optimal cache reuse, and group related `RUN` steps.
* **Linting:** Use `hadolint` to lint Dockerfiles before committing; it must exit clean. Silence a rule only in `.hadolint.yaml` with the reason next to it — not inline, not via `failure-threshold`.
* **Scanning:** Scan images for vulnerabilities (e.g., `docker scout` or `trivy`) and inspect layers/size (e.g., `dive`); ensure no high-severity issues and no unnecessary bloat remain before committing.

## Project Structure

* `Dockerfile.<target>` — one Dockerfile per image target (e.g., `Dockerfile.gba`).

## Dockerfile Style Guide

* **Multi-Stage Builds:** Build toolchains in a builder stage; the final stage only `COPY --from=` the installed prefix. No build trees, source archives, or compilers in the published image.
* **Pinning:** Pin base images by tag and upstream sources by commit SHA or version, as `ARG`s before the first `FROM` (one source of truth for the build and the labels), re-declared bare in each consuming stage.
* **Integrity:** Verify downloaded archives with `sha256sum -c` when a checksum `ARG` is set. An empty checksum skips the check; a mismatch always fails.
* **Layer Caching:** Order slowest-changing first — package installs, pinned `ARG`s, source fetch, build. Never put a frequently bumped `ARG` above `apt-get install`.
* **Layer Hygiene:** One `RUN` per build step, cleanup in the same layer (`rm -rf /var/lib/apt/lists/*`, archives, build dirs) — deleting later does not shrink the image.
* **Packages:** `apt-get update -qq && apt-get install -y --no-install-recommends` in a single `RUN`; comment why non-obvious packages are needed.
* **Shell Safety:** Use `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` in any stage that pipes, so mid-pipeline failures fail the build.
* **Runtime User:** No `USER` directive. As GitHub Actions job containers the runner bind-mounts `/__w` as the host runner user and starts the container without `--user`, so a baked-in non-root user breaks `actions/checkout` with `EACCES`. Local runs pass `--user "$(id -u):$(id -g)"` themselves.
* **Build Context:** Images fetch their own sources; the context stays empty — never `COPY` host files into a toolchain image.
* **Multi-Arch:** Build `linux/amd64` and `linux/arm64`. arm64 runs under QEMU — parallelize with `$(nproc)` and raise the caller's timeout instead of dropping the platform.
* **Smoke Test:** The builder stage must exercise the toolchain it built (compile an upstream example, print the compiler version), so breakage fails the build, not the consumer.
* **Labels:** Static OCI and `com.toygine2.*` labels live in the Dockerfile; CI injects only `created`, `revision`, `version`.
* **Comments:** Explain *why* — the trade-off, upstream quirk, ordering constraint — not what the command does.

## Package Management

* **Package Source:** Use the base image's package manager (`apt-get`, `dkp-pacman`); an upstream archive only when no package works — pinned and verified per **Integrity**.
* **Newer Versions:** Too old for the consumer — take that one package from an official suite (`-t bookworm-backports cmake`), never swap the base image or add a third-party repo. Comment the required minimum and who needs it.
* **Adding Packages:** Only when a concrete build or CI step fails without it. Extend the stage's existing `apt-get install` instead of adding a `RUN`, and comment *why*.
* **Build vs Runtime Deps:** Compilers, `-dev` packages, and build-only tools stay in the builder; the final image gets the shared libs its binaries link against and what the CI job runs inside it — fetch/unpack tools (`curl`, `xz-utils`, `unzip`) included.
* **Removing Packages:** Delete from the original install list; a later `purge`/`rm` layer does not shrink the image.
* **Verification:** Rebuild the affected stage `--no-cache` and run `<tool> --version` against the version the consumer requires. No fix is claimed without that output.
* **Cost:** Report the size delta and added attack surface (`dive`, `docker scout` per **Scanning**); drop convenience-only packages.

## Code Quality

* **Separation of Concerns:** One responsibility per stage — sources build in a builder, reach the final image via `COPY --from=` (**Multi-Stage Builds**). The consumer's toolchain stays; what built it does not.
* **RUN Granularity:** One logical step per `RUN` — fetch, build+install, its own cleanup — chained with `&&`, wrapped with `\`. Cleanup never moves to the next `RUN` (**Layer Hygiene**).
* **Naming:** `SCREAMING_SNAKE_CASE` for `ARG`/`ENV`, lowercase-hyphen for stages, `Dockerfile.<target>` for files. Namespace runtime `ENV` by its SDK (`CLOWNMDSDK`, `DEVKITPRO`) — generic `PREFIX`/`CC`/`TARGET` leak into mounted consumer builds.
* **Conciseness:** The shortest instruction that stays clear. Never re-set what the base image provides, or add an `ARG` with one possible value.
* **Simplicity:** Plain shell. Clever quoting, nested subshells, and generated scripts are unreviewable inside a layer — that much logic belongs upstream.
* **Error Handling:** Fail loudly — `&&` between fallible commands (syntactic `;` as in `if …; then` is fine), `pipefail` (**Shell Safety**), `curl -fSL --retry`, `sha256sum -c` (**Integrity**). No `|| true`, no `/dev/null` hiding failures.
* **Styling:** Instructions UPPERCASE; wrap at 100 columns except URLs and `LABEL` values; package lists in a stable order.
* **Testing:** Prove the image in-build (**Smoke Test**) — compile something real, print the version. A `SKIP_SMOKE_TEST` `ARG` only where the test dominates build time.
* **Build Output:** Signal only — `apt-get -qq`, `curl -fSL` not `-#`, no `echo` narration. The failing step's stderr is the log.
