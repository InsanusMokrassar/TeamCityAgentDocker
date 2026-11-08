#!/usr/bin/env bash
set -euo pipefail
trap 'echo "FAIL: smoke-test.sh line $LINENO: $BASH_COMMAND" >&2' ERR

[[ $(id -un) == buildagent ]]
[[ $(id -u) != 0 ]]
for tool in bash git python3 gpg node npm sdkmanager chromium chromium-browser; do
    command -v "$tool"
done
java -version
java -XshowSettings:properties -version 2>&1 | grep 'java.specification.version = 21$'
javac -version
node --version
npm --version
python3 --version
git --version
sdkmanager --version
chromium --version | grep '^Chromium '
chromium-browser --version | grep '^Chromium '
[[ -x /run-services.sh && -x /opt/buildagent/bin/agent.sh ]]
[[ "$CONFIG_FILE" == /data/teamcity_agent/conf/buildAgent.properties ]]
[[ "$ANDROID_HOME" == "$ANDROID_SDK_ROOT" && -w "$ANDROID_HOME" ]]
[[ -s "$ANDROID_HOME/platforms/android-$ANDROID_API/android.jar" ]]
[[ -s "$ANDROID_HOME/licenses/android-sdk-license" ]]

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf 'class Hello { public static void main(String[] a) { System.out.println("JAVA_OK"); } }\n' > "$work/Hello.java"
javac --release 21 "$work/Hello.java"
[[ $(java -cp "$work" Hello) == JAVA_OK ]]

# Exercise a real native Android tool, not just SDK directory existence.
aapt2="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION/aapt2"
"$aapt2" version
mkdir -p "$work/res/values"
printf '<resources><string name="app_name">Agent smoke test</string></resources>\n' > "$work/res/values/strings.xml"
"$aapt2" compile --dir "$work/res" -o "$work/resources.zip"
printf '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.inmo.agentsmoke"><uses-sdk android:minSdkVersion="26"/><application android:label="@string/app_name"/></manifest>\n' > "$work/AndroidManifest.xml"
"$aapt2" link -o "$work/smoke.apk" --manifest "$work/AndroidManifest.xml" \
    -I "$ANDROID_HOME/platforms/android-$ANDROID_API/android.jar" "$work/resources.zip"
[[ -s "$work/smoke.apk" ]]

# Execute JavaScript in a real headless Chromium process, without network access.
printf '<html><body><script>document.body.textContent="CHROMIUM_OK"</script></body></html>\n' > "$work/browser.html"
timeout 60 "$CHROME_BIN" --headless --disable-gpu --dump-dom \
    "file://$work/browser.html" > "$work/browser-output.html" 2> "$work/browser.log" \
    || { cat "$work/browser.log" >&2; exit 1; }
python3 - "$work/browser-output.html" <<'PY'
import pathlib, re, sys
html = pathlib.Path(sys.argv[1]).read_text()
assert re.search(r'<body>\s*CHROMIUM_OK\s*</body>', html), html
PY
echo "PASS: non-root agent, Java 21 compilation, Android resources and Chromium JavaScript ($(uname -m))"
