#!/usr/bin/env bash

xforce_caddy_tunnel_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_caddy_tunnel_enabled() {
  value="$1"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON|auto|quick|named) return 0 ;;
    *) return 1 ;;
  esac
}

xforce_caddy_write_env() {
  status="$1"
  reason="${2:-}"
  mkdir -p /tmp/xforce-ai/caddy
  {
    printf 'XFORCE_CADDY_STATUS=%s\n' "$status"
    printf 'XFORCE_CADDY_REASON=%s\n' "$reason"
    printf 'XFORCE_CADDY_HTTP_ADDR=%s\n' "${XFORCE_CADDY_HTTP_ADDR:-:8088}"
    printf 'XFORCE_CADDY_CONFIG=%s\n' "${XFORCE_CADDY_GENERATED_CONFIG:-/tmp/xforce-ai/caddy/Caddyfile.generated}"
    printf 'XFORCE_CADDY_ROUTES=%s\n' "${XFORCE_CADDY_ROUTES:-/etc/xforce-ai/caddy/routes.yaml}"
  } > /tmp/xforce-ai/caddy/caddy.env
}

xforce_tunnel_write_env() {
  status="$1"
  mode="${2:-auto}"
  reason="${3:-}"
  mkdir -p /tmp/xforce-ai/tunnel
  {
    printf 'XFORCE_TUNNEL_STATUS=%s\n' "$status"
    printf 'XFORCE_TUNNEL_MODE=%s\n' "$mode"
    printf 'XFORCE_TUNNEL_REASON=%s\n' "$reason"
    printf 'XFORCE_TUNNEL_TOKEN_CONFIGURED=%s\n' "$(if [ -n "${CF_TUNNEL_TOKEN:-}" ]; then printf true; else printf false; fi)"
    printf 'XFORCE_TUNNEL_METRICS=%s\n' "${XFORCE_TUNNEL_METRICS:-127.0.0.1:20241}"
  } > /tmp/xforce-ai/tunnel/tunnel.env
}

xforce_supervisor_socket_ready() {
  [ -S "${XFORCE_SUPERVISOR_SOCKET:-/tmp/xforce-ai/supervisor/supervisor.sock}" ]
}

xforce_caddy_tunnel_main() {
  export XFORCE_CADDY_ON_BOOT="${XFORCE_CADDY_ON_BOOT:-auto}"
  export XFORCE_TUNNEL_ON_BOOT="${XFORCE_TUNNEL_ON_BOOT:-auto}"
  export XFORCE_CADDY_HTTP_ADDR="${XFORCE_CADDY_HTTP_ADDR:-:8088}"
  export XFORCE_CADDY_ADMIN_ADDR="${XFORCE_CADDY_ADMIN_ADDR:-127.0.0.1:2019}"
  export XFORCE_CADDY_GENERATED_CONFIG="${XFORCE_CADDY_GENERATED_CONFIG:-/tmp/xforce-ai/caddy/Caddyfile.generated}"
  export XFORCE_CADDY_ROUTES="${XFORCE_CADDY_ROUTES:-/etc/xforce-ai/caddy/routes.yaml}"
  export XFORCE_CADDY_AUTH="${XFORCE_CADDY_AUTH:-/etc/xforce-ai/caddy/auth.yaml}"
  export XFORCE_TUNNEL_METRICS="${XFORCE_TUNNEL_METRICS:-127.0.0.1:20241}"
  export XFORCE_CLOUDFLARED_BIN="${XFORCE_CLOUDFLARED_BIN:-cloudflared}"

  mkdir -p /tmp/xforce-ai/caddy /tmp/xforce-ai/tunnel /tmp/xforce-ai/services/caddy /tmp/xforce-ai/services/cloudflared /etc/caddy

  if ! xforce_caddy_tunnel_enabled "$XFORCE_CADDY_ON_BOOT"; then
    xforce_caddy_write_env disabled disabled
    xforce_caddy_tunnel_log info caddy "status=disabled"
  elif command -v xforce-caddy >/dev/null 2>&1 || [ -x /opt/xforce-ai/bin/xforce-caddy ]; then
    caddy_cli="$(command -v xforce-caddy || true)"
    caddy_cli="${caddy_cli:-/opt/xforce-ai/bin/xforce-caddy}"
    if "$caddy_cli" render >/dev/null; then
      if command -v caddy >/dev/null 2>&1; then
        if caddy validate --config "$XFORCE_CADDY_GENERATED_CONFIG" --adapter caddyfile >/dev/null 2>&1; then
          xforce_caddy_write_env rendered ""
        else
          xforce_caddy_write_env invalid validate_failed
        fi
      else
        xforce_caddy_write_env rendered caddy_missing
      fi
      if xforce_supervisor_socket_ready; then
        supervisorctl -c "${XFORCE_SUPERVISOR_CONFIG:-/etc/supervisor/supervisord.conf}" start caddy >/dev/null 2>&1 || true
      fi
      xforce_caddy_tunnel_log info caddy "status=rendered config=$XFORCE_CADDY_GENERATED_CONFIG"
    else
      xforce_caddy_write_env failed render_failed
      xforce_caddy_tunnel_log error caddy "status=failed reason=render_failed"
    fi
  else
    xforce_caddy_write_env skipped cli_missing
    xforce_caddy_tunnel_log warn caddy "status=skipped reason=cli_missing"
  fi

  tunnel_mode="$XFORCE_TUNNEL_ON_BOOT"
  if [ "$tunnel_mode" = auto ] && [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
    tunnel_mode=named
  fi
  case "$tunnel_mode" in
    0|false|FALSE|no|NO|off|OFF|auto)
      xforce_tunnel_write_env skipped "$tunnel_mode" token_missing_quick_not_requested
      ;;
    quick|named)
      xforce_tunnel_write_env ready "$tunnel_mode" ""
      if xforce_supervisor_socket_ready; then
        supervisorctl -c "${XFORCE_SUPERVISOR_CONFIG:-/etc/supervisor/supervisord.conf}" start cloudflared >/dev/null 2>&1 || true
      fi
      ;;
    *)
      xforce_tunnel_write_env skipped "$tunnel_mode" unknown_mode
      ;;
  esac
}

xforce_caddy_tunnel_main
