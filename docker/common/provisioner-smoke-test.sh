#!/usr/bin/env bash
set -Eeuo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export PYTHONPATH="${PYTHONPATH:-$(pwd)/docker/common}"

sha_file() {
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
}

mkdir -p "$tmp/workspace" "$tmp/state" "$tmp/cache" "$tmp/bin" "$tmp/venv/main/bin" "$tmp/repo-src" "$tmp/repo-dest"
python3 -m venv "$tmp/venv/main"
printf 'data-file\n' > "$tmp/source.txt"
download_sha="$(sha_file "$tmp/source.txt")"
printf 'model-file\n' > "$tmp/model.gguf"
model_sha="$(sha_file "$tmp/model.gguf")"
: > "$tmp/requirements.txt"

cat > "$tmp/bin/apt-get" <<'EOF_APT'
#!/usr/bin/env bash
echo "apt-get $*" >> "${XFORCE_FAKE_APT_LOG:?}"
if [ "${XFORCE_FAKE_APT_FAIL_ONCE:-0}" = "1" ] && [ ! -f "${XFORCE_FAKE_APT_MARKER:?}" ]; then
  touch "${XFORCE_FAKE_APT_MARKER:?}"
  exit 1
fi
exit 0
EOF_APT
chmod 0755 "$tmp/bin/apt-get"

git init -q "$tmp/repo-src"
git -C "$tmp/repo-src" config user.email test@example.invalid
git -C "$tmp/repo-src" config user.name test
printf 'hello\n' > "$tmp/repo-src/README.md"
git -C "$tmp/repo-src" add README.md
git -C "$tmp/repo-src" commit -q -m init

cat > "$tmp/provisioning.yaml" <<EOF_MANIFEST
apiVersion: xforce.ai/v1
kind: ProvisioningManifest
metadata:
  name: smoke
stages:
  - id: apt-fixture
    type: apt
    packages:
      - fake-package
  - id: pip-fixture
    type: pip
    venv: $tmp/venv/main
    requirements:
      - $tmp/requirements.txt
  - id: git-fixture
    type: git
    repo: $tmp/repo-src
    dest: $tmp/workspace/repo
    ref: master
  - id: download-fixture
    type: download
    url: file://$tmp/source.txt
    dest: $tmp/workspace/source.txt
    sha256: $download_sha
  - id: model-fixture
    type: model
    url: file://$tmp/model.gguf
    dest: $tmp/workspace/models/model.gguf
    sha256: $model_sha
    format: gguf
EOF_MANIFEST

export XFORCE_APT_GET_BIN="$tmp/bin/apt-get"
export XFORCE_FAKE_APT_LOG="$tmp/apt.log"
export XFORCE_FAKE_APT_MARKER="$tmp/apt.marker"
export XFORCE_FAKE_APT_FAIL_ONCE=1
export XFORCE_PROVISION_MAX_RETRIES=1
export XFORCE_PROVISION_BACKOFF_BASE_SECONDS=0
export XFORCE_PROVISION_BACKOFF_MAX_SECONDS=0

xforce_cmd="${XFORCE_PROVISION_BIN:-/opt/xforce-ai/bin/xforce-provision}"
if [ ! -x "$xforce_cmd" ]; then
  xforce_cmd="python3 -m provisioner"
fi

$xforce_cmd validate --manifest "$tmp/provisioning.yaml" --state-dir "$tmp/state"
$xforce_cmd plan --manifest "$tmp/provisioning.yaml" --state-dir "$tmp/state" --venv-dir "$tmp/venv/main" --workspace-dir "$tmp/workspace" | grep -q '^run apt apt-fixture'
$xforce_cmd run --manifest "$tmp/provisioning.yaml" --state-dir "$tmp/state" --cache-dir "$tmp/cache" --venv-dir "$tmp/venv/main" --workspace-dir "$tmp/workspace"
$xforce_cmd plan --manifest "$tmp/provisioning.yaml" --state-dir "$tmp/state" --venv-dir "$tmp/venv/main" --workspace-dir "$tmp/workspace" | grep -q '^skip apt apt-fixture'

[ -f "$tmp/workspace/source.txt" ]
[ -f "$tmp/workspace/models/model.gguf" ]
[ -f "$tmp/state/models.json" ]
[ -d "$tmp/workspace/repo/.git" ]
grep -q 'apt-get update' "$tmp/apt.log"

cat > "$tmp/duplicate.yaml" <<'EOF_DUP'
apiVersion: xforce.ai/v1
kind: ProvisioningManifest
stages:
  - id: same
    type: apt
    packages: [a]
  - id: same
    type: apt
    packages: [b]
EOF_DUP
if $xforce_cmd validate --manifest "$tmp/duplicate.yaml" --state-dir "$tmp/state" >/dev/null 2>&1; then
  echo "duplicate stage validation unexpectedly succeeded" >&2
  exit 1
fi

echo "xforce_AI provisioner smoke test passed"
