#!/usr/bin/env bash
set -Eeuo pipefail

portal_base="http://${XFORCE_PORTAL_HOST:-127.0.0.1}:${XFORCE_PORTAL_PORT:-8080}"
ipfs_api="${XFORCE_IPFS_API_URL:-http://127.0.0.1:5001}"
ipfs_gateway="${XFORCE_IPFS_GATEWAY_ORIGIN:-http://127.0.0.1:8081}"
outputs_dir="${XFORCE_OUTPUTS_DIR:-/workspace/outputs}"

wait_http() {
  url="$1"
  timeout="${2:-30}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

wait_ipfs_api() {
  url="$1"
  timeout="${2:-30}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if curl -fsS -X POST "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

if [ ! -S "${XFORCE_SUPERVISOR_SOCKET:-/tmp/xforce-ai/supervisor/supervisor.sock}" ]; then
  # shellcheck disable=SC1091
  . /etc/xforce_ai_boot.d/60-supervisor.sh
fi

wait_ipfs_api "$ipfs_api/api/v0/id" 45
curl -fsS -X POST "$ipfs_api/api/v0/id" | grep -q '"ID"'

wait_http "$portal_base/api/v1/health" 30
curl -fsS "$portal_base/api/v1/ipfs/status" | grep -q '"enabled":true'

mkdir -p "$outputs_dir"
sample="$outputs_dir/ipfs-smoke.txt"
printf 'xforce ipfs smoke %s\n' "$(date -u +%s)" > "$sample"

curl -fsS "$portal_base/api/v1/files/outputs" | grep -Eq 'queued|pinned|uploading'

cid=""
for _ in $(seq 1 40); do
  json="$(curl -fsS "$portal_base/api/v1/files/outputs")"
  cid="$(printf '%s' "$json" | python3 -c 'import json, sys; data=json.load(sys.stdin); print(next(((entry.get("ipfs") or {}).get("cid", "") for entry in data.get("entries", []) if entry.get("name") == "ipfs-smoke.txt"), ""))')"
  if [ -n "$cid" ]; then
    break
  fi
  sleep 1
done

if [ -z "$cid" ]; then
  echo "expected IPFS CID for $sample" >&2
  exit 1
fi

curl -fsS "$ipfs_gateway/ipfs/$cid" | grep -q 'xforce ipfs smoke'

PYTHONPATH="${PYTHONPATH:-/opt/portal-aio}" python3 - <<'PY'
from portal.files import FileRoot, safe_child
from pathlib import Path
root = FileRoot("outputs", Path("/workspace/outputs").resolve())
try:
    safe_child(root, "../../etc/passwd")
except Exception:
    pass
else:
    raise SystemExit("path traversal was not rejected")
PY

echo "xforce_AI F014 IPFS smoke test passed"
