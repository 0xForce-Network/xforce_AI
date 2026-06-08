#!/usr/bin/env bash

xforce_workspace_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_workspace_bool_enabled() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) [ -d "${WORKSPACE_DIR:-/workspace}" ] && [ -w "${WORKSPACE_DIR:-/workspace}" ] ;;
  esac
}

xforce_workspace_write_state() {
  status="$1"
  copied="${2:-0}"
  state_dir="${XFORCE_SYNC_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  {
    printf 'XFORCE_SYNC_WORKSPACE_STATUS=%s\n' "$status"
    printf 'XFORCE_SYNC_WORKSPACE_DIR=%s\n' "${WORKSPACE_DIR:-/workspace}"
    printf 'XFORCE_SYNC_STATE_DIR=%s\n' "${XFORCE_PERSISTENCE_STATE_DIR:-${WORKSPACE_DIR:-/workspace}/.xforce-state}"
    printf 'XFORCE_SYNC_WORKSPACE_COPIED=%s\n' "$copied"
  } > "${state_dir}/workspace-sync.env"
}

xforce_workspace_write_summary() {
  state_dir="${XFORCE_SYNC_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  workspace_status="$(grep -E '^XFORCE_SYNC_WORKSPACE_STATUS=' "${state_dir}/workspace-sync.env" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
  home_status="$(grep -E '^XFORCE_SYNC_HOME_STATUS=' "${state_dir}/home-sync.env" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
  venv_status="$(grep -E '^XFORCE_SYNC_VENV_STATUS=' "${state_dir}/venv-sync.env" 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
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

xforce_workspace_with_lock() {
  lock_dir="$1"
  shift
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "30" ]; then
      xforce_workspace_log error workspace-sync "status=error reason=lock_timeout lock=${lock_dir}"
      return 1
    fi
    sleep 1
  done
  "$@"
  rc=$?
  rmdir "$lock_dir" 2>/dev/null || true
  return "$rc"
}

xforce_workspace_copy_seed() {
  seed_dir="$1"
  workspace="$2"
  copied=0
  [ -d "$seed_dir" ] || return 2
  for item in "$seed_dir"/* "$seed_dir"/.[!.]* "$seed_dir"/..?*; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    [ "$name" = "." ] && continue
    [ "$name" = ".." ] && continue
    target="${workspace}/${name}"
    if [ -e "$target" ] || [ -L "$target" ]; then
      continue
    fi
    cp -a "$item" "$target"
    copied=$((copied + 1))
  done
  printf '%s\n' "$copied" > "${XFORCE_PERSISTENCE_STATE_DIR}/workspace-seed.copied"
}

xforce_workspace_sync_main() {
  workspace="${WORKSPACE_DIR:-/workspace}"
  seed_dir="${XFORCE_WORKSPACE_SEED_DIR:-/opt/xforce-ai/share/workspace-seed}"
  export XFORCE_PERSISTENCE_STATE_DIR="${XFORCE_PERSISTENCE_STATE_DIR:-${workspace}/.xforce-state}"
  if ! xforce_workspace_bool_enabled "${XFORCE_SYNC_PERSISTENCE:-auto}" || ! xforce_workspace_bool_enabled "${XFORCE_SYNC_WORKSPACE:-auto}"; then
    xforce_workspace_write_state disabled 0
    xforce_workspace_write_summary
    xforce_workspace_log info workspace-sync "status=disabled"
    return 0
  fi
  mkdir -p "$workspace"
  if [ ! -w "$workspace" ]; then
    xforce_workspace_write_state skipped 0
    xforce_workspace_write_summary
    xforce_workspace_log warn workspace-sync "status=skipped reason=workspace_not_writable path=${workspace}"
    return 0
  fi
  mkdir -p "${XFORCE_PERSISTENCE_STATE_DIR}/locks"
  if [ ! -d "$seed_dir" ]; then
    xforce_workspace_write_state skipped 0
    xforce_workspace_write_summary
    xforce_workspace_log info workspace-sync "status=skipped reason=seed_missing"
    return 0
  fi
  xforce_workspace_with_lock "${XFORCE_PERSISTENCE_STATE_DIR}/locks/workspace-seed.lock" xforce_workspace_copy_seed "$seed_dir" "$workspace" || return 1
  copied="$(cat "${XFORCE_PERSISTENCE_STATE_DIR}/workspace-seed.copied" 2>/dev/null || printf '0')"
  xforce_workspace_write_state synced "$copied"
  xforce_workspace_write_summary
  xforce_workspace_log info workspace-sync "status=synced copied=${copied}"
}

xforce_workspace_sync_main
