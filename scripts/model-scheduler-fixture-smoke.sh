#!/usr/bin/env bash
set -Eeuo pipefail

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 -m hil_orchestrator preflight \
  --model-id stable-diffusion-xl \
  --request-id preflight-sdxl \
  --max-price-per-hour 1.00 > "$tmp/preflight-sdxl.json"
grep -q '"status": "available"' "$tmp/preflight-sdxl.json"
grep -q 'NVIDIA GeForce RTX 4090' "$tmp/preflight-sdxl.json"

set +e
python3 -m hil_orchestrator preflight --model-id giant-vram-model --request-id preflight-giant > "$tmp/preflight-giant.json"
status="$?"
set -e
if [ "$status" -ne 3 ]; then
  echo "expected unavailable preflight exit code 3, got $status" >&2
  exit 1
fi
grep -q '"status": "unavailable"' "$tmp/preflight-giant.json"
grep -q 'min_vram_not_satisfied' "$tmp/preflight-giant.json"

python3 -m hil_orchestrator preflight \
  --model-id tiny-llm-smoke \
  --allow-degraded \
  --request-id preflight-tiny > "$tmp/preflight-tiny.json"
grep -q '"status": "available"' "$tmp/preflight-tiny.json"

python3 -m hil_orchestrator book \
  --model-id stable-diffusion-xl \
  --request-id booking-req-001 \
  --lock-dir "$tmp/locks" > "$tmp/lock-1.json"
lock_id="$(python3 - "$tmp/lock-1.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["lock_id"])
PY
)"
grep -q '"state": "held"' "$tmp/lock-1.json"

python3 -m hil_orchestrator book \
  --model-id stable-diffusion-xl \
  --request-id booking-req-001 \
  --lock-dir "$tmp/locks" > "$tmp/lock-retry.json"
grep -q "$lock_id" "$tmp/lock-retry.json"

set +e
python3 -m hil_orchestrator book \
  --model-id stable-diffusion-xl \
  --request-id booking-req-002 \
  --lock-dir "$tmp/locks" > "$tmp/lock-conflict.json"
status="$?"
set -e
if [ "$status" -ne 4 ]; then
  echo "expected lock conflict exit code 4, got $status" >&2
  cat "$tmp/lock-conflict.json" >&2
  exit 1
fi
grep -q 'lock_conflict' "$tmp/lock-conflict.json"

python3 -m hil_orchestrator commit --lock-id "$lock_id" --booking-id booking-final-001 --lock-dir "$tmp/locks" | grep -q '"state": "committed"'
python3 -m hil_orchestrator release --lock-id "$lock_id" --lock-dir "$tmp/locks" | grep -q '"state": "released"'

echo "xforce_AI F012 scheduler fixture smoke passed"
