#!/usr/bin/env bash

xforce_supervisor_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_supervisor_enabled() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    0|false|FALSE|no|NO|off|OFF) return 1 ;;
    *) return 2 ;;
  esac
}

xforce_supervisor_write_state() {
  status="$1"
  reason="${2:-}"
  state_dir="${XFORCE_PORTAL_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}/portal}"
  mkdir -p "$state_dir"
  {
    printf 'XFORCE_SUPERVISOR_STATUS=%s\n' "$status"
    printf 'XFORCE_SUPERVISOR_REASON=%s\n' "$reason"
    printf 'XFORCE_SUPERVISOR_CONFIG=%s\n' "${XFORCE_SUPERVISOR_CONFIG:-/etc/supervisor/supervisord.conf}"
    printf 'XFORCE_SUPERVISOR_SOCKET=%s\n' "${XFORCE_SUPERVISOR_SOCKET:-/tmp/xforce-ai/supervisor/supervisor.sock}"
    printf 'XFORCE_PORTAL_STATUS=%s\n' "${XFORCE_PORTAL_STATUS:-unknown}"
    printf 'XFORCE_PORTAL_HOST=%s\n' "${XFORCE_PORTAL_HOST:-127.0.0.1}"
    printf 'XFORCE_PORTAL_PORT=%s\n' "${XFORCE_PORTAL_PORT:-8080}"
  } > "$state_dir/portal.env"
}

xforce_supervisor_wait_socket() {
  socket_path="$1"
  timeout="${2:-10}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if [ -S "$socket_path" ]; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

xforce_supervisor_main() {
  export XFORCE_SUPERVISOR_ON_BOOT="${XFORCE_SUPERVISOR_ON_BOOT:-auto}"
  export XFORCE_PORTAL_ON_BOOT="${XFORCE_PORTAL_ON_BOOT:-auto}"
  export XFORCE_PORTAL_HOST="${XFORCE_PORTAL_HOST:-127.0.0.1}"
  export XFORCE_PORTAL_PORT="${XFORCE_PORTAL_PORT:-8080}"
  export XFORCE_SUPERVISOR_CONFIG="${XFORCE_SUPERVISOR_CONFIG:-/etc/supervisor/supervisord.conf}"
  export XFORCE_SUPERVISOR_SOCKET="${XFORCE_SUPERVISOR_SOCKET:-/tmp/xforce-ai/supervisor/supervisor.sock}"
  export XFORCE_SUPERVISOR_STATE_DIR="${XFORCE_SUPERVISOR_STATE_DIR:-/tmp/xforce-ai/supervisor}"
  export XFORCE_SERVICE_LOG_DIR="${XFORCE_SERVICE_LOG_DIR:-/tmp/xforce-ai/services}"

  mkdir -p "$XFORCE_SUPERVISOR_STATE_DIR/logs" "$XFORCE_SERVICE_LOG_DIR/portal-backend" "$XFORCE_SERVICE_LOG_DIR/example-pty-service" "$XFORCE_SERVICE_LOG_DIR/ipfs-daemon" "$XFORCE_SERVICE_LOG_DIR/caddy" "$XFORCE_SERVICE_LOG_DIR/cloudflared" "${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}/portal" /tmp/xforce-ai/pty /tmp/xforce-ai/metrics

  case "$XFORCE_SUPERVISOR_ON_BOOT" in
    0|false|FALSE|no|NO|off|OFF)
      XFORCE_PORTAL_STATUS=disabled
      xforce_supervisor_write_state disabled disabled
      xforce_supervisor_log info supervisor "status=disabled"
      return 0
      ;;
  esac

  if [ ! -f "$XFORCE_SUPERVISOR_CONFIG" ]; then
    if xforce_supervisor_enabled "$XFORCE_SUPERVISOR_ON_BOOT"; then
      XFORCE_PORTAL_STATUS=failed
      xforce_supervisor_write_state failed config_missing
      xforce_supervisor_log error supervisor "status=failed reason=config_missing"
      return 1
    fi
    XFORCE_PORTAL_STATUS=skipped
    xforce_supervisor_write_state skipped config_missing
    xforce_supervisor_log info supervisor "status=skipped reason=config_missing"
    return 0
  fi

  if ! command -v supervisord >/dev/null 2>&1; then
    XFORCE_PORTAL_STATUS=failed
    xforce_supervisor_write_state failed supervisord_missing
    xforce_supervisor_log error supervisor "status=failed reason=supervisord_missing"
    return 1
  fi

  if [ -S "$XFORCE_SUPERVISOR_SOCKET" ]; then
    if supervisorctl -c "$XFORCE_SUPERVISOR_CONFIG" status >/dev/null 2>&1; then
      xforce_supervisor_log info supervisor "status=already_running socket=$XFORCE_SUPERVISOR_SOCKET"
    else
      rm -f "$XFORCE_SUPERVISOR_SOCKET" "${XFORCE_SUPERVISOR_STATE_DIR}/supervisord.pid"
      xforce_supervisor_log info supervisor "status=stale_socket_removed socket=$XFORCE_SUPERVISOR_SOCKET"
      supervisord -c "$XFORCE_SUPERVISOR_CONFIG"
    fi
  else
    supervisord -c "$XFORCE_SUPERVISOR_CONFIG"
  fi

  if ! xforce_supervisor_wait_socket "$XFORCE_SUPERVISOR_SOCKET" 10; then
    XFORCE_PORTAL_STATUS=failed
    xforce_supervisor_write_state failed socket_timeout
    xforce_supervisor_log error supervisor "status=failed reason=socket_timeout"
    return 1
  fi

  if xforce_supervisor_enabled "$XFORCE_PORTAL_ON_BOOT" || [ "$XFORCE_PORTAL_ON_BOOT" = auto ]; then
    XFORCE_PORTAL_STATUS=enabled
  else
    XFORCE_PORTAL_STATUS=disabled
    supervisorctl -c "$XFORCE_SUPERVISOR_CONFIG" stop portal-backend >/dev/null 2>&1 || true
  fi
  xforce_supervisor_write_state running ""
  xforce_supervisor_log info supervisor "status=running socket=$XFORCE_SUPERVISOR_SOCKET portal=$XFORCE_PORTAL_STATUS"
}

xforce_supervisor_main
