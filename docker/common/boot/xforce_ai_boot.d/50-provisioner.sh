#!/usr/bin/env bash

xforce_provision_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_provision_write_state() {
  status="$1"
  manifest="${2:-}"
  source="${3:-none}"
  error="${4:-}"
  state_dir="${XFORCE_PROVISION_BOOT_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  {
    printf 'XFORCE_PROVISION_STATUS=%s\n' "$status"
    printf 'XFORCE_PROVISION_MANIFEST=%s\n' "$manifest"
    printf 'XFORCE_PROVISION_MANIFEST_SOURCE=%s\n' "$source"
    printf 'XFORCE_PROVISION_STATE_DIR=%s\n' "${XFORCE_PROVISION_STATE_DIR:-/.provisioner_state}"
    printf 'XFORCE_PROVISION_STAGE_TOTAL=%s\n' 0
    printf 'XFORCE_PROVISION_STAGE_COMPLETED=%s\n' 0
    printf 'XFORCE_PROVISION_STAGE_SKIPPED=%s\n' 0
    printf 'XFORCE_PROVISION_STAGE_FAILED=%s\n' 0
    printf 'XFORCE_PROVISION_LAST_ERROR=%s\n' "$error"
  } > "${state_dir}/provisioner.env"
}

xforce_provision_bool_enabled() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) return 2 ;;
  esac
}

xforce_provision_find_manifest() {
  if [ -n "${XFORCE_PROVISION_MANIFEST:-}" ]; then
    printf '%s\n' "$XFORCE_PROVISION_MANIFEST"
    return 0
  fi
  for candidate in \
    "${WORKSPACE_DIR:-/workspace}/provisioning.yaml" \
    "${WORKSPACE_DIR:-/workspace}/provisioning.yml" \
    "/etc/xforce-ai/provisioning.yaml"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

xforce_provision_main() {
  export XFORCE_PROVISION_STATE_DIR="${XFORCE_PROVISION_STATE_DIR:-/.provisioner_state}"
  export XFORCE_PROVISION_CACHE_DIR="${XFORCE_PROVISION_CACHE_DIR:-${XFORCE_PROVISION_STATE_DIR}/downloads}"
  export XFORCE_PROVISION_MANIFEST_CACHE_DIR="${XFORCE_PROVISION_MANIFEST_CACHE_DIR:-${XFORCE_PROVISION_STATE_DIR}/manifests}"
  export XFORCE_PROVISION_BOOT_STATE_DIR="${XFORCE_PROVISION_BOOT_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"

  mode="${XFORCE_PROVISION_ON_BOOT:-auto}"
  case "$mode" in
    0|false|FALSE|no|NO|off|OFF)
      xforce_provision_write_state disabled "" none ""
      xforce_provision_log info provisioner "status=disabled"
      return 0
      ;;
  esac

  manifest="$(xforce_provision_find_manifest || true)"
  if [ -z "$manifest" ]; then
    case "$mode" in
      1|true|TRUE|yes|YES|on|ON)
        xforce_provision_write_state failed "" none "manifest_not_found"
        xforce_provision_log error provisioner "status=failed reason=manifest_not_found"
        return 1
        ;;
    esac
    xforce_provision_write_state skipped "" none ""
    xforce_provision_log info provisioner "status=skipped reason=manifest_missing"
    return 0
  fi

  python_bin="${VENV_DIR:-/venv/main}/bin/python"
  if [ ! -x "$python_bin" ]; then
    python_bin="$(command -v python3)"
  fi
  export PYTHONPATH="/opt/xforce-ai/lib:${PYTHONPATH:-}"
  xforce_provision_log info provisioner "status=running manifest=${manifest}"
  "$python_bin" -m provisioner run --manifest "$manifest" --state-dir "$XFORCE_PROVISION_STATE_DIR"
}

xforce_provision_main
