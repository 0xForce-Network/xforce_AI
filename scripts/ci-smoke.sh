#!/usr/bin/env bash
set -Eeuo pipefail

mode="${1:-smoke}"

case "$mode" in
  preflight)
    make check-naming
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git diff --check
    fi
    PYTHONPATH=docker/common python3 -m compileall docker/common/provisioner docker/common/pty_wrapper docker/common/portal docker/common/caddy_manager docker/common/tunnel_manager
    python3 -m compileall hil_orchestrator
    python3 -m hil_orchestrator validate-config --models configs/hil/model-requirements.yaml --suites configs/hil/hil-suites.yaml --inventory configs/hil/fixture-gpu-inventory.yaml >/dev/null
    bash -n docker/common/*.sh docker/common/boot/*.sh docker/common/boot/xforce_ai_boot.d/*.sh scripts/*.sh
    bash scripts/hil-fixture-smoke.sh
    bash scripts/model-scheduler-fixture-smoke.sh
    ;;
  smoke)
    tag="${IMAGE_TAG:-f011-smoke}"
    ENABLE_NUSHELL="${ENABLE_NUSHELL:-0}" \
    ENABLE_CLOUDFLARED="${ENABLE_CLOUDFLARED:-0}" \
    IMAGE_TAG="$tag" \
    PLATFORMS="${PLATFORMS:-linux/amd64}" \
    PUSH=0 \
    LOAD=1 \
    scripts/build-image.sh cpu
    docker run --rm "${IMAGE_REGISTRY:-ghcr.io/xforce-ai}/${IMAGE_NAME:-xforce-ai}:cpu-${tag}" /opt/xforce-ai/bin/smoke-test.sh
    ;;
  *)
    echo "usage: scripts/ci-smoke.sh [preflight|smoke]" >&2
    exit 2
    ;;
esac
