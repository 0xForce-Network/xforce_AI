#!/usr/bin/env bash

if [ "${XFORCE_SKIP_READY_MARKER:-0}" = "1" ]; then
  boot_log info ready "marker=skipped"
  return 0
fi

mkdir -p "$XFORCE_BOOT_STATE_DIR"
{
  printf 'variant=%s\n' "${XFORCE_IMAGE_VARIANT:-unknown}"
  printf 'version=%s\n' "${XFORCE_IMAGE_VERSION:-dev}"
  printf 'started_at=%s\n' "${XFORCE_BOOT_STARTED_AT:-unknown}"
  printf 'ready_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${XFORCE_BOOT_STATE_DIR}/boot-ready"

boot_log info ready "marker=${XFORCE_BOOT_STATE_DIR}/boot-ready"
