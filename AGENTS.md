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
* **Linting:** Use `hadolint` to lint Dockerfiles and fix flagged issues before committing.
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
