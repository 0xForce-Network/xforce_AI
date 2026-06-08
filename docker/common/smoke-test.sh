#!/usr/bin/env bash
set -Eeuo pipefail

required_paths=(
  /opt/xforce-ai/bin/entrypoint.sh
  /opt/xforce-ai/bin/boot_default.sh
  /opt/xforce-ai/lib
  /opt/portal-aio
  /etc/xforce_ai_boot.d
  /etc/xforce_ai_boot.d/00-env.sh
  /etc/xforce_ai_boot.d/99-ready.sh
  /etc/supervisor/conf.d
  /venv/main
  /workspace
  /home/user
)

for path in "${required_paths[@]}"; do
  if [ ! -e "$path" ]; then
    echo "missing required path: $path" >&2
    exit 1
  fi
done

if [ ! -x /opt/xforce-ai/bin/entrypoint.sh ]; then
  echo "entrypoint is not executable" >&2
  exit 1
fi

if [ ! -x /opt/xforce-ai/bin/boot_default.sh ]; then
  echo "default boot script is not executable" >&2
  exit 1
fi

if [ ! -f /tmp/xforce-ai/boot-ready ]; then
  echo "boot ready marker missing" >&2
  exit 1
fi

grep -q '^variant=' /tmp/xforce-ai/boot-ready
grep -q '^version=' /tmp/xforce-ai/boot-ready

python3 --version
/venv/main/bin/python --version
echo "xforce_AI F003 smoke test passed"
