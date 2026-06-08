#!/usr/bin/env bash
set -Eeuo pipefail

echo "xforce_AI container bootstrap placeholder"
echo "variant=${XFORCE_IMAGE_VARIANT:-unknown}"
echo "version=${XFORCE_IMAGE_VERSION:-dev}"
echo "workspace=${WORKSPACE_DIR:-/workspace}"
echo "venv=${VENV_DIR:-/venv/main}"
echo "notice=temporary F002 entrypoint; F003 will replace this with the POSIX boot loader"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

exec "${SHELL:-/bin/bash}" -l
