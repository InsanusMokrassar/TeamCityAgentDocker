#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

platform=${PLATFORM:-linux/$(docker info --format '{{.Architecture}}')}
case "$platform" in
    linux/x86_64) platform=linux/amd64 ;;
    linux/aarch64) platform=linux/arm64 ;;
    linux/amd64|linux/arm64) ;;
    *) echo "Unsupported platform: $platform" >&2; exit 1 ;;
esac
base=${TEAMCITY_AGENT_IMAGE:-jetbrains/teamcity-agent:latest}
image=${IMAGE:-teamcity-agent:test-${platform##*/}}

# No login, no credentials and no push. Extra arguments are Docker build args/options.
docker buildx build --pull --load --platform "$platform" \
    --build-arg "TEAMCITY_AGENT_IMAGE=$base" \
    --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --build-arg "VCS_REF=$(git rev-parse --verify HEAD 2>/dev/null || printf local)" \
    --tag "$image" "$@" .
./scripts/test-image.sh "$image" "$base" "$platform"
