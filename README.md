# TeamCity Agent Docker

An image **based on the official `jetbrains/teamcity-agent:latest`** for
Java/Kotlin, Android, and browser tests. Supported platforms: `linux/amd64` and
`linux/arm64` (including Raspberry Pi 5 running a 64-bit OS).
It inherits the original TeamCity startup mechanism instead of replacing it.

## Included tools

- The official TeamCity agent, JDK 21, Git, and the base image's other tools.
- Python 3, GnuPG, curl, CA certificates, zip/unzip, and xz.
- Node.js 24 LTS and npm from the official multi-platform Node image.
- Real **Chromium** and its Linux dependencies from the signed
  [XtraDeb PPA](https://launchpad.net/~xtradeb/+archive/ubuntu/apps) for Ubuntu
  24.04. No Google Chrome, Chrome for Testing, or Ubuntu Snap.
- Both `chromium` and `chromium-browser` commands; `CHROME_BIN` is set automatically.
- Android Command-line Tools **21.0 / 15641748**, SDK platform **37.0**,
  Build Tools **37.0.0**, platform-tools, and accepted SDK licenses.
- `ANDROID_HOME` and `ANDROID_SDK_ROOT` are `/opt/android-sdk`. The SDK is writable
  by `buildagent`. `/opt/android-sdk/platforms/android-37` is also available for
  existing API 37 preflight checks.

Chromium runs with `--no-sandbox --disable-dev-shm-usage` for containerized CI
tests. No Snap, privileged container, or package installation during project
builds is required. Daily image rebuilds update Chromium through apt.
PPA pinning limits it to Chromium packages, and its signing key is checked
against its full fingerprint. The build explicitly checks for Ubuntu 24.04:
if upstream changes the OS, it fails rather than mixing distribution releases.

### ARM64 details

Java, Node, Chromium, and the agent run natively. Google's Android SDK ZIP still
contains several x86 Linux host tools, so the ARM64 image provides:

- Native `aapt2` **9.5.1-16666295 from official Google Maven**, not an unofficial
  ARM binary mirror.
- `ORG_GRADLE_PROJECT_android.aapt2FromMavenOverride`, preventing older AGP
  releases, including 9.1.x, from downloading an x86-only `aapt2`.
- Native Ubuntu packages for `aapt`, `aidl`, `zipalign`, `adb`, and `fastboot`.
  Their versions differ from the tools in Google's SDK ZIP.

Command-line Tools are pinned to the Java-based `sdkmanager`. The newer 23.0
archive replaces it with a launcher for a native Android CLI, which is not
suitable for the same installation procedure on both architectures.

The smoke test actually compiles and links Android resources on each
architecture. It does not cover the NDK, Android emulator, hardware tests, or
an entire arbitrary Android project. Other native SDK utilities are not
claimed to support ARM merely because their files exist in the image.

## Replace an existing agent

After the first successful publication, change **only the image name** in the
existing container configuration:

```yaml
image: insanusmokrassar/teamcity-agent:latest
# Or pin a build date: insanusmokrassar/teamcity-agent:YYYY-MM-DD
```

Keep the existing `SERVER_URL`, `AGENT_NAME`, `AGENT_TOKEN`, networks, and volumes,
including `/data/teamcity_agent/conf` and `/opt/buildagent/*`. The persisted
configuration retains the agent's authorization. The default user remains
`buildagent` (UID/GID 1000). `CMD`, `ENTRYPOINT`, `WORKDIR`, and volumes are
inherited from the official image. Root is used only while building the image.

This repository **does not modify or restart an existing agent** by itself.

## Local testing without secrets or publishing

The testing host needs Docker with Buildx, Bash, Python 3, and Git:

```bash
./scripts/test-local.sh
```

This builds and loads the image into local Docker, runs the smoke test as
`buildagent`, and compares its startup contract with the official image.
It never runs `docker login` or `docker push`.

```bash
PLATFORM=linux/amd64 ./scripts/test-local.sh
PLATFORM=linux/arm64 ./scripts/test-local.sh  # Native on a Pi 5 or another ARM64 host
./scripts/test-local.sh --no-cache          # Rebuild all dependencies from scratch
```

Cross-architecture testing requires Docker/QEMU emulation configured beforehand.
The script does not change the host's binfmt configuration. GitHub Actions
tests both architectures on **native runners**, without QEMU.

The smoke test checks Java 21 compilation, tools, SDK write permissions,
actual Android resource compilation/linking, and JavaScript execution in
headless Chromium. Image metadata checks verify the original agent's startup
command, user, volumes, and working directory.

Override Dockerfile parameters with `--build-arg`, for example:

```bash
./scripts/test-local.sh --build-arg ANDROID_API=37.0
```

Set `TEAMCITY_AGENT_IMAGE` to pin the official base tag or digest. A multi-platform
build needs a base tag containing both Linux architectures: not all tags ending
in `-linux` include ARM64. Upstream Java/Ubuntu changes must pass the smoke test
rather than being assumed compatible.

## GitHub Actions and Docker Hub

Two independent workflows are provided:

1. **Build and test (no publishing)** runs on pushes to `main`, pull requests,
   and manual dispatch. It builds and tests both architectures. **No secrets
   are needed.**
2. **Daily Docker Hub publication** runs daily at **02:43 UTC / 08:43 Omsk** or
   on manual dispatch. It rebuilds both architectures with fresh base images and
   no cache, tests them, pushes the tested images, and creates the multi-platform
   manifest.

Add the following repository secrets in Settings → Secrets and variables →
Actions. These are the same names used by
[JenkinsDocker](https://github.com/InsanusMokrassar/JenkinsDocker/blob/master/.github/workflows/docker-publish.yml):

| Secret | Value |
| --- | --- |
| `DOCKER_LOGIN` | Docker Hub login with write access to `insanusmokrassar/teamcity-agent` |
| `DOCKER_PASSWORD` | Docker Hub access token with Read & Write permission |

GitHub does **not** automatically copy repository secrets between repositories.
Until both secrets are configured, the publication workflow skips publication
cleanly; the separate test workflow remains usable. After adding the secrets,
run the publication workflow manually or wait for its next scheduled run.
Create the public Docker Hub repository `insanusmokrassar/teamcity-agent` if
the account does not create it automatically on the first push.

Published tags:

- `insanusmokrassar/teamcity-agent:YYYY-MM-DD`: multi-platform, using the UTC date
  when the workflow starts.
- `insanusmokrassar/teamcity-agent:latest`: the latest successful multi-platform build.
- `YYYY-MM-DD-amd64` and `YYYY-MM-DD-arm64`: the corresponding tested platform images.

A rerun on the same day updates that day's tags. The shared date and `latest`
tags are updated only after both platform tests succeed; a failed platform does
not advance `latest`. GitHub may delay scheduled runs and disables scheduled
workflows in inactive public repositories after 60 days; re-enable them if needed.

## Repository language

Use English for documentation, code comments, workflow names, commit messages,
issues, and pull requests.
