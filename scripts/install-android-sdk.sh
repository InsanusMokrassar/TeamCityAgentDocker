#!/usr/bin/env bash
set -euo pipefail

archive=$(mktemp --suffix=.zip)
curl --fail --location --retry 5 \
    "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_COMMANDLINE_TOOLS_VERSION}_latest.zip" \
    --output "$archive"
# Checksum from Google's repository2-3.xml for this exact release.
printf '%s  %s\n' "$ANDROID_COMMANDLINE_TOOLS_SHA1" "$archive" | sha1sum --check -
mkdir -p "$ANDROID_HOME/cmdline-tools"
unzip -q "$archive" -d "$ANDROID_HOME/cmdline-tools"
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
rm "$archive"

# yes gets SIGPIPE when sdkmanager finishes; check sdkmanager, not yes.
set +o pipefail
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
set -o pipefail
sdkmanager --sdk_root="$ANDROID_HOME" --install \
    "platform-tools" "platforms;android-${ANDROID_API}" \
    "build-tools;${ANDROID_BUILD_TOOLS_VERSION}"

# Some existing projects/preflight checks still address API 37 as android-37.
if [[ "$ANDROID_API" == *.0 ]]; then
    ln -s "android-${ANDROID_API}" "$ANDROID_HOME/platforms/android-${ANDROID_API%.0}"
fi

if [[ "$TARGETARCH" == arm64 ]]; then
    # Google's SDK ZIP still ships x86 Linux host tools. Supply native tools on ARM.
    # aapt2 comes from official Google Maven, not an unofficial ARM binary mirror.
    apt-get update
    apt-get install -y --no-install-recommends aapt aidl zipalign adb fastboot
    tools="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION"
    artifact="https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/${ARM64_AAPT2_VERSION}/aapt2-${ARM64_AAPT2_VERSION}-linux_arm64.jar"
    archive=$(mktemp --suffix=.jar)
    curl --fail --location --retry 5 "$artifact" --output "$archive"
    checksum=$(curl --fail --location --retry 5 "${artifact}.sha1")
    printf '%s  %s\n' "$checksum" "$archive" | sha1sum --check -
    # The ARM64 binary uses the bundled musl loader and libc++; extracting only
    # aapt2 produces a valid ARM ELF that cannot actually start.
    unzip -oq "$archive" aapt2 'lib64/*' -d "$tools"
    chmod 755 "$tools/aapt2" "$tools/lib64/libc_musl.so" "$tools/lib64/libc++.so"
    rm "$archive"
    for tool in aapt aidl zipalign; do ln -sf "/usr/bin/$tool" "$tools/$tool"; done
    for tool in adb fastboot; do ln -sf "/usr/bin/$tool" "$ANDROID_HOME/platform-tools/$tool"; done
fi
sdkmanager --version
"$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION/aapt2" version
