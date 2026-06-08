#!/usr/bin/env bash

xforce_venv_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_venv_bool_enabled() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) [ -d "${WORKSPACE_DIR:-/workspace}" ] && [ -w "${WORKSPACE_DIR:-/workspace}" ] ;;
  esac
}

xforce_venv_state_value() {
  file="$1"
  key="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

xforce_venv_write_summary() {
  state_dir="${XFORCE_SYNC_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  workspace_status="$(xforce_venv_state_value "${state_dir}/workspace-sync.env" XFORCE_SYNC_WORKSPACE_STATUS)"
  home_status="$(xforce_venv_state_value "${state_dir}/home-sync.env" XFORCE_SYNC_HOME_STATUS)"
  venv_status="$(xforce_venv_state_value "${state_dir}/venv-sync.env" XFORCE_SYNC_VENV_STATUS)"
  persistence_status=enabled
  if [ "${XFORCE_SYNC_PERSISTENCE:-auto}" = "0" ]; then
    persistence_status=disabled
  fi
  {
    printf 'XFORCE_SYNC_PERSISTENCE_STATUS=%s\n' "$persistence_status"
    printf 'XFORCE_SYNC_WORKSPACE_STATUS=%s\n' "${workspace_status:-pending}"
    printf 'XFORCE_SYNC_HOME_STATUS=%s\n' "${home_status:-pending}"
    printf 'XFORCE_SYNC_VENV_STATUS=%s\n' "${venv_status:-pending}"
    printf 'XFORCE_SYNC_WORKSPACE_DIR=%s\n' "${WORKSPACE_DIR:-/workspace}"
    printf 'XFORCE_SYNC_STATE_DIR=%s\n' "${XFORCE_PERSISTENCE_STATE_DIR:-${WORKSPACE_DIR:-/workspace}/.xforce-state}"
  } > "${state_dir}/persistence.env"
}

xforce_venv_write_state() {
  status="$1"
  target="${2:-}"
  env_id="${3:-}"
  state_dir="${XFORCE_SYNC_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  {
    printf 'XFORCE_SYNC_VENV_STATUS=%s\n' "$status"
    printf 'XFORCE_SYNC_VENV_TARGET=%s\n' "$target"
    printf 'XFORCE_SYNC_ENV_ID=%s\n' "$env_id"
  } > "${state_dir}/venv-sync.env"
  xforce_venv_write_summary
}

xforce_venv_env_id() {
  venv_dir="$1"
  if [ -n "${XFORCE_ENV_ID:-}" ]; then
    printf '%s\n' "$XFORCE_ENV_ID"
    return 0
  fi
  py_version="unknown"
  if [ -x "${venv_dir}/bin/python" ]; then
    py_version="$(${venv_dir}/bin/python -c 'import sys; print(f"py{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || printf 'unknown')"
  fi
  printf '%s-%s-%s' "${XFORCE_IMAGE_VARIANT:-unknown}" "${XFORCE_IMAGE_VERSION:-dev}" "$py_version" | tr -c 'A-Za-z0-9_.-' '_'
}

xforce_venv_with_lock() {
  lock_dir="$1"
  shift
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt "60" ] || return 1
    sleep 1
  done
  "$@"
  rc=$?
  rmdir "$lock_dir" 2>/dev/null || true
  return "$rc"
}

xforce_venv_copy_and_link() {
  source_venv="$1"
  link_venv="$2"
  target_venv="$3"
  mkdir -p "$(dirname "$target_venv")"
  if [ ! -e "$target_venv" ]; then
    mkdir -p "$target_venv"
    touch "${target_venv}.syncing"
    cp -a "${source_venv}/." "$target_venv/"
    rm -f "${target_venv}.syncing"
  fi
  if [ "$(readlink -f "$link_venv" 2>/dev/null || true)" = "$(readlink -f "$target_venv" 2>/dev/null || true)" ]; then
    return 0
  fi
  if [ -L "$link_venv" ]; then
    current_target="$(readlink "$link_venv")"
    [ "$current_target" = "$target_venv" ] || ln -sfn "$target_venv" "$link_venv"
  else
    rm -rf "$link_venv"
    ln -s "$target_venv" "$link_venv"
  fi
}

xforce_venv_sync_main() {
  workspace="${WORKSPACE_DIR:-/workspace}"
  source_venv="${VENV_DIR:-/venv/main}"
  export XFORCE_PERSISTENCE_STATE_DIR="${XFORCE_PERSISTENCE_STATE_DIR:-${workspace}/.xforce-state}"
  if ! xforce_venv_bool_enabled "${XFORCE_SYNC_PERSISTENCE:-auto}" || ! xforce_venv_bool_enabled "${XFORCE_SYNC_VENV:-auto}"; then
    xforce_venv_write_state disabled "" ""
    xforce_venv_log info venv-sync "status=disabled"
    return 0
  fi
  if [ ! -w "$workspace" ]; then
    xforce_venv_write_state skipped "" ""
    xforce_venv_log warn venv-sync "status=skipped reason=workspace_not_writable"
    return 0
  fi
  if [ ! -d "$source_venv" ] && [ ! -L "$source_venv" ]; then
    xforce_venv_write_state skipped "" ""
    xforce_venv_log warn venv-sync "status=skipped reason=venv_missing path=${source_venv}"
    return 0
  fi
  real_source="$(readlink -f "$source_venv" 2>/dev/null || printf '%s' "$source_venv")"
  if [ ! -f "${real_source}/pyvenv.cfg" ] && [ ! -x "${real_source}/bin/python" ]; then
    xforce_venv_write_state skipped "" ""
    xforce_venv_log warn venv-sync "status=skipped reason=not_a_venv path=${source_venv}"
    return 0
  fi
  env_id="$(xforce_venv_env_id "$real_source")"
  target_venv="${XFORCE_PERSISTENCE_STATE_DIR}/environment/${env_id}/venv/main"
  mkdir -p "${XFORCE_PERSISTENCE_STATE_DIR}/locks"
  xforce_venv_with_lock "${XFORCE_PERSISTENCE_STATE_DIR}/locks/venv-main.lock" xforce_venv_copy_and_link "$real_source" "$source_venv" "$target_venv" || return 1
  xforce_venv_write_state synced "$target_venv" "$env_id"
  xforce_venv_log info venv-sync "status=synced env_id=${env_id} target=${target_venv}"
}

xforce_venv_sync_main
