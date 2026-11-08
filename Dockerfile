# syntax=docker/dockerfile:1
ARG TEAMCITY_AGENT_IMAGE=jetbrains/teamcity-agent:latest
ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE} AS node

FROM ${TEAMCITY_AGENT_IMAGE} AS toolchain
ARG TARGETARCH
ARG ANDROID_COMMANDLINE_TOOLS_VERSION=15641748
ARG ANDROID_COMMANDLINE_TOOLS_SHA1=63523a02a975a81102238566f2a16c057d52301e
ARG ANDROID_API=37.0
ARG ANDROID_BUILD_TOOLS_VERSION=37.0.0
ARG ARM64_AAPT2_VERSION=9.5.1-16666295

# Root is used only while building the image. The agent still runs as buildagent.
USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git gnupg python3 unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_API=${ANDROID_API} \
    ANDROID_BUILD_TOOLS_VERSION=${ANDROID_BUILD_TOOLS_VERSION} \
    CHROME_BIN=/usr/local/bin/chromium
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS_VERSION}:${PATH}"

COPY --chmod=755 scripts/install-android-sdk.sh /usr/local/lib/agent-image/
RUN /usr/local/lib/agent-image/install-android-sdk.sh \
    && chown -R buildagent:buildagent "${ANDROID_HOME}" \
    && rm -rf /var/lib/apt/lists/*
COPY --chmod=755 scripts/chromium /usr/local/bin/chromium
COPY --chmod=755 scripts/install-chromium.sh /usr/local/lib/agent-image/
RUN /usr/local/lib/agent-image/install-chromium.sh \
    && ln -s chromium /usr/local/bin/chromium-browser \
    && rm -rf /var/lib/apt/lists/*
COPY --chmod=755 scripts/smoke-test.sh /usr/local/bin/agent-smoke-test
USER buildagent

FROM toolchain AS agent-amd64

FROM toolchain AS agent-arm64
# Older AGP releases otherwise download an x86-only aapt2 on Linux ARM64.
# Gradle reads ORG_GRADLE_PROJECT_* directly, including dots in property names.
ENV ORG_GRADLE_PROJECT_android.aapt2FromMavenOverride="${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS_VERSION}/aapt2"

FROM agent-${TARGETARCH} AS final
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.title="TeamCity Agent with Android SDK and Chromium" \
      org.opencontainers.image.source="https://github.com/InsanusMokrassar/TeamCityAgentDocker" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"
# Deliberately inherit CMD, ENTRYPOINT, WORKDIR, volumes and connection handling.
