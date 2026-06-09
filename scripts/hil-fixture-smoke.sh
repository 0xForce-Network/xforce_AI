#!/usr/bin/env bash
set -Eeuo pipefail

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 -m hil_orchestrator validate-config --models configs/hil/model-requirements.yaml --suites configs/hil/hil-suites.yaml --inventory configs/hil/fixture-gpu-inventory.yaml | grep -q '"status": "ok"'

python3 -m hil_orchestrator run-validation \
  --suite-id nvidia-base-ai-smoke \
  --provider fixture \
  --node-id miner-node-001 \
  --state-dir "$tmp/state" \
  --artifact-dir "$tmp/artifacts" > "$tmp/report-pass.json"
grep -q '"certification_state": "Certified_Active"' "$tmp/report-pass.json"
grep -q 'hil-artifact' "$tmp/report-pass.json"

python3 -m hil_orchestrator run-validation \
  --suite-id miner-activation-basic \
  --provider fixture \
  --node-id miner-node-001 \
  --state-dir "$tmp/state-degraded" \
  --artifact-dir "$tmp/artifacts-degraded" > "$tmp/report-degraded.json"
grep -q '"certification_state": "Certified_Degraded"' "$tmp/report-degraded.json"

set +e
python3 -m hil_orchestrator run-validation \
  --suite-id fixture-required-failure \
  --provider fixture \
  --node-id miner-node-001 \
  --state-dir "$tmp/state-fail" \
  --artifact-dir "$tmp/artifacts-fail" > "$tmp/report-fail.json"
status="$?"
set -e
if [ "$status" -ne 0 ]; then
  echo "fixture required failure command should emit failed report with exit 0" >&2
  exit 1
fi
grep -q '"certification_state": "Certification_Failed"' "$tmp/report-fail.json"

report_path="$(python3 - "$tmp/report-pass.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["report_path"])
PY
)"
python3 -m hil_orchestrator inspect-report --report "$report_path" | grep -q '"status": "passed"'

echo "xforce_AI F012 HIL fixture smoke passed"
