#!/usr/bin/env bash
set -Eeuo pipefail

required_paths=(
  /opt/xforce-ai/bin/entrypoint.sh
  /opt/xforce-ai/lib
  /opt/portal-aio
  /etc/xforce_ai_boot.d
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

python3 --version
/venv/main/bin/python --version
echo "xforce_AI F002 smoke test passed"
