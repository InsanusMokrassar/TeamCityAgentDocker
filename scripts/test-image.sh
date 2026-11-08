#!/usr/bin/env bash
set -euo pipefail
image=${1:?Usage: test-image.sh IMAGE BASE_IMAGE PLATFORM}
base=${2:?Missing base image}
platform=${3:?Missing platform}
docker run --rm --platform "$platform" --entrypoint /usr/local/bin/agent-smoke-test "$image"

# The image must remain a drop-in agent, not merely a container with SDK files.
docker pull --platform "$platform" "$base"
python3 - "$base" "$image" "$platform" <<'PY'
import json, subprocess, sys
help_text = subprocess.check_output(['docker', 'image', 'inspect', '--help'], text=True)
# Older Docker stores one architecture per tag and has no inspect --platform.
# The preceding pull --platform already selects it on those engines.
options = ['--platform', sys.argv[3]] if '--platform' in help_text else []
base, image = json.loads(subprocess.check_output([
    'docker', 'image', 'inspect', *options, *sys.argv[1:3]
]))
for field in ('User', 'Entrypoint', 'Cmd', 'WorkingDir', 'Volumes'):
    assert base['Config'].get(field) == image['Config'].get(field), f'Changed base contract: {field}'
assert image['Architecture'] == base['Architecture'] == sys.argv[3].split('/')[1]
print('PASS: original TeamCity user, startup command, volumes and working directory preserved')
PY
