#!/usr/bin/env bash
set -euo pipefail

# Ubuntu's chromium-browser redirects to Snap. XtraDeb publishes real Chromium
# deb packages for Ubuntu, including native amd64 and arm64 builds.
# Pin this PPA to Chromium packages instead of upgrading unrelated base packages.
# shellcheck source=/dev/null
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_CODENAME" == noble ]] || {
    echo 'This image currently supports the official Ubuntu 24.04 TeamCity base.' >&2
    exit 1
}
fingerprint=5301FA4FD93244FBC6F6149982BB6851C64F6880
key=$(mktemp)
curl --fail --location --retry 5 \
    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${fingerprint}" --output "$key"
actual=$(gpg --batch --show-keys --with-colons "$key" | awk -F: '$1 == "fpr" { print $10; exit }')
[[ "$actual" == "$fingerprint" ]]
gpg --batch --yes --dearmor --output /usr/share/keyrings/xtradeb-apps.gpg "$key"
rm "$key"
printf 'deb [arch=%s signed-by=/usr/share/keyrings/xtradeb-apps.gpg] https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu noble main\n' \
    "$TARGETARCH" > /etc/apt/sources.list.d/xtradeb-chromium.list
cat > /etc/apt/preferences.d/xtradeb-chromium <<'PINS'
Package: chromium chromium-common chromium-sandbox chromium-driver chromium-l10n
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 600

Package: *
Pin: release o=LP-PPA-xtradeb-apps
Pin-Priority: 100
PINS
apt-get update
apt-get install -y --no-install-recommends chromium chromium-sandbox fonts-liberation fonts-noto-color-emoji
/usr/local/bin/chromium --version
