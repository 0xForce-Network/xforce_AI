#!/usr/bin/env bash

xforce_home_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_home_bool_enabled() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) [ -d "${WORKSPACE_DIR:-/workspace}" ] && [ -w "${WORKSPACE_DIR:-/workspace}" ] ;;
  esac
}

xforce_home_state_value() {
  file="$1"
  key="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

xforce_home_write_summary() {
  state_dir="${XFORCE_SYNC_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  workspace_status="$(xforce_home_state_value "${state_dir}/workspace-sync.env" XFORCE_SYNC_WORKSPACE_STATUS)"
  home_status="$(xforce_home_state_value "${state_dir}/home-sync.env" XFORCE_SYNC_HOME_STATUS)"
  venv_status="$(xforce_home_state_value "${state_dir}/venv-sync.env" XFORCE_SYNC_VENV_STATUS)"
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

xforce_home_write_state() {
  status="$1"
  target="${2:-}"
  state_dir="${XFORCE_SYNC_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
  mkdir -p "$state_dir"
  {
    printf 'XFORCE_SYNC_HOME_STATUS=%s\n' "$status"
    printf 'XFORCE_SYNC_HOME_TARGET=%s\n' "$target"
    printf 'XFORCE_SYNC_SSH_TO_WORKSPACE=%s\n' "${XFORCE_SYNC_SSH_TO_WORKSPACE:-0}"
  } > "${state_dir}/home-sync.env"
  xforce_home_write_summary
}

xforce_home_with_lock() {
  lock_dir="$1"
  shift
  attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt "30" ] || return 1
    sleep 1
  done
  "$@"
  rc=$?
  rmdir "$lock_dir" 2>/dev/null || true
  return "$rc"
}

xforce_home_copy_and_link() {
  source_home="$1"
  persisted_home="$2"
  username="$3"
  ssh_home="$4"
  mkdir -p "$(dirname "$persisted_home")" "$ssh_home"
  if [ ! -e "$persisted_home" ]; then
    mkdir -p "$persisted_home"
    cp -a "${source_home}/." "$persisted_home/" 2>/dev/null || true
  fi
  if [ "${XFORCE_SYNC_SSH_TO_WORKSPACE:-0}" != "1" ]; then
    mkdir -p "${ssh_home}/${username}"
    if [ -d "${persisted_home}/.ssh" ] && [ ! -e "${ssh_home}/${username}/.ssh" ]; then
      mv "${persisted_home}/.ssh" "${ssh_home}/${username}/.ssh" 2>/dev/null || true
    fi
    mkdir -p "${ssh_home}/${username}/.ssh"
    chmod 700 "${ssh_home}/${username}/.ssh" 2>/dev/null || true
  fi
  if [ -L "$source_home" ]; then
    current_target="$(readlink "$source_home")"
    [ "$current_target" = "$persisted_home" ] || ln -sfn "$persisted_home" "$source_home"
  else
    rm -rf "$source_home"
    ln -s "$persisted_home" "$source_home"
  fi
  if [ "${XFORCE_SYNC_SSH_TO_WORKSPACE:-0}" != "1" ]; then
    ln -sfn "${ssh_home}/${username}/.ssh" "${source_home}/.ssh" 2>/dev/null || true
  fi
}

xforce_home_sync_main() {
  workspace="${WORKSPACE_DIR:-/workspace}"
  export XFORCE_PERSISTENCE_STATE_DIR="${XFORCE_PERSISTENCE_STATE_DIR:-${workspace}/.xforce-state}"
  if ! xforce_home_bool_enabled "${XFORCE_SYNC_PERSISTENCE:-auto}" || ! xforce_home_bool_enabled "${XFORCE_SYNC_HOME:-auto}"; then
    xforce_home_write_state disabled ""
    xforce_home_log info home-sync "status=disabled"
    return 0
  fi
  if [ ! -w "$workspace" ]; then
    xforce_home_write_state skipped ""
    xforce_home_log warn home-sync "status=skipped reason=workspace_not_writable"
    return 0
  fi
  user_name="${XFORCE_USER:-user}"
  source_home="${XFORCE_TEST_USER_HOME:-/home/${user_name}}"
  persisted_home="${XFORCE_PERSISTENCE_STATE_DIR}/home/${user_name}"
  ssh_home="${XFORCE_CONTAINER_SSH_HOME:-/home_ssh}"
  mkdir -p "${XFORCE_PERSISTENCE_STATE_DIR}/locks"
  if [ ! -d "$source_home" ] && [ ! -L "$source_home" ]; then
    xforce_home_write_state skipped "$persisted_home"
    xforce_home_log warn home-sync "status=skipped reason=home_missing path=${source_home}"
    return 0
  fi
  xforce_home_with_lock "${XFORCE_PERSISTENCE_STATE_DIR}/locks/home-${user_name}.lock" xforce_home_copy_and_link "$source_home" "$persisted_home" "$user_name" "$ssh_home" || return 1
  chown -h "${XFORCE_UID:-1000}:${XFORCE_GID:-1000}" "$source_home" 2>/dev/null || true
  chown -R "${XFORCE_UID:-1000}:${XFORCE_GID:-1000}" "$persisted_home" 2>/dev/null || true
  xforce_home_write_state synced "$persisted_home"
  xforce_home_log info home-sync "status=synced user=${user_name} target=${persisted_home}"
}

xforce_home_sync_main
