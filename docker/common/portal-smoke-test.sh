#!/usr/bin/env bash
set -Eeuo pipefail

portal_base="http://${XFORCE_PORTAL_HOST:-127.0.0.1}:${XFORCE_PORTAL_PORT:-8080}"

wait_http() {
  url="$1"
  timeout="${2:-20}"
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

if [ ! -S "${XFORCE_SUPERVISOR_SOCKET:-/tmp/xforce-ai/supervisor/supervisor.sock}" ]; then
  # shellcheck disable=SC1091
  . /etc/xforce_ai_boot.d/60-supervisor.sh
fi

wait_http "$portal_base/api/v1/health" 30
curl -fsS "$portal_base/api/v1/health" | grep -q '"status":"ok"'
curl -fsS "$portal_base/api/v1/services" | grep -q 'example-pty-service'
curl -fsS "$portal_base/api/v1/metrics" | grep -q '"cpu"'
curl -fsS "$portal_base/api/v1/metrics/gpu" | grep -q '"providers"'
curl -fsS "$portal_base/api/v1/files" | grep -q '"roots"'
curl -fsS "$portal_base/api/v1/ipfs/status" | grep -q '"autoMaxBytes"'
curl -fsS "$portal_base/api/v1/portal-assets/file-browser.js" | grep -q 'XForceFileBrowser'

tmp="$(mktemp -d)"
mkdir -p "$tmp/cgroups-v2" "$tmp/cgroups-v1" "$tmp/fake-bin"
cat > "$tmp/cgroups-v2/cgroup.controllers" <<'EOF_CG'
cpu memory
EOF_CG
cat > "$tmp/cgroups-v2/cpu.stat" <<'EOF_CPU_STAT'
usage_usec 123456
throttled_usec 7
EOF_CPU_STAT
printf '50000 100000\n' > "$tmp/cgroups-v2/cpu.max"
printf '4096\n' > "$tmp/cgroups-v2/memory.current"
printf '8192\n' > "$tmp/cgroups-v2/memory.max"
cat > "$tmp/cgroups-v2/memory.stat" <<'EOF_MEM_STAT'
anon 1024
file 2048
kernel 512
EOF_MEM_STAT
printf '123456000\n' > "$tmp/cgroups-v1/cpuacct.usage"
printf '100000\n' > "$tmp/cgroups-v1/cpu.cfs_quota_us"
printf '100000\n' > "$tmp/cgroups-v1/cpu.cfs_period_us"
printf '4096\n' > "$tmp/cgroups-v1/memory.usage_in_bytes"
printf '9223372036854771712\n' > "$tmp/cgroups-v1/memory.limit_in_bytes"
cat > "$tmp/cgroups-v1/memory.stat" <<'EOF_MEM_STAT_V1'
rss 1024
cache 2048
EOF_MEM_STAT_V1
cat > "$tmp/fake-bin/rocm-smi" <<'EOF_ROCM'
#!/usr/bin/env bash
cat <<'EOF_JSON'
{"card0":{"Card series":"Fake AMD GPU","GPU use (%)":"12%","VRAM Total Used Memory (B)":"1024","VRAM Total Memory (B)":"2048","Temperature (Sensor edge) (C)":"44"}}
EOF_JSON
EOF_ROCM
chmod 0755 "$tmp/fake-bin/rocm-smi"

PYTHONPATH=/opt/portal-aio XFORCE_CGROUP_ROOT="$tmp/cgroups-v2" XFORCE_ROCM_SMI_BIN="$tmp/fake-bin/rocm-smi" python3 - <<'PY'
from portal.metrics.cpu import read_cpu_metrics
from portal.metrics.memory import read_memory_metrics
from portal.metrics.rocm import read_rocm_metrics
from pathlib import Path
import os
root = Path(os.environ["XFORCE_CGROUP_ROOT"])
assert read_cpu_metrics(root)["quotaCores"] == 0.5
assert read_memory_metrics(root)["limitBytes"] == 8192
assert read_rocm_metrics()["available"] is True
PY
PYTHONPATH=/opt/portal-aio XFORCE_CGROUP_ROOT="$tmp/cgroups-v1" python3 - <<'PY'
from portal.metrics.cpu import read_cpu_metrics
from portal.metrics.memory import read_memory_metrics
from pathlib import Path
import os
root = Path(os.environ["XFORCE_CGROUP_ROOT"])
assert read_cpu_metrics(root)["usageUsec"] == 123456
assert read_memory_metrics(root)["limitBytes"] is None
PY

curl -fsS -X POST "$portal_base/api/v1/services/example-pty-service/start" | grep -Eq 'RUNNING|STARTING'
sleep 2
curl -fsS "$portal_base/api/v1/services/example-pty-service/logs?stream=plain&limit=4096" | grep -q 'content'
curl -fsS -X POST "$portal_base/api/v1/services/example-pty-service/stop" | grep -Eq 'STOPPED|STOPPING|EXITED'
protected_status="$(curl -sS -o "$tmp/protected.json" -w '%{http_code}' -X POST "$portal_base/api/v1/services/portal-backend/stop")"
if [ "$protected_status" != "403" ]; then
  cat "$tmp/protected.json" >&2
  echo "expected protected stop HTTP 403, got $protected_status" >&2
  exit 1
fi
grep -q 'protected_service' "$tmp/protected.json"
rm -rf "$tmp"

echo "xforce_AI F009 portal smoke test passed"
