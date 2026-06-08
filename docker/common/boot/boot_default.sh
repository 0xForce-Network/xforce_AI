#!/usr/bin/env bash
set -eu

umask 002

XFORCE_BOOT_ROOT="${XFORCE_BOOT_ROOT:-/opt/xforce-ai}"
XFORCE_BOOT_DIR="${XFORCE_BOOT_DIR:-/etc/xforce_ai_boot.d}"
XFORCE_BOOT_STATE_DIR="${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}"
XFORCE_BOOT_STARTED_AT="${XFORCE_BOOT_STARTED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
XFORCE_SKIP_READY_MARKER=0
XFORCE_DEBUG_BOOT=0
XFORCE_PRINT_ENV=0
XFORCE_SOURCE_BOOT_FRAGMENTS=1

export XFORCE_BOOT_ROOT XFORCE_BOOT_DIR XFORCE_BOOT_STATE_DIR XFORCE_BOOT_STARTED_AT
export XFORCE_IMAGE_VARIANT="${XFORCE_IMAGE_VARIANT:-unknown}"
export XFORCE_IMAGE_VERSION="${XFORCE_IMAGE_VERSION:-dev}"
export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export VENV_DIR="${VENV_DIR:-/venv/main}"
case ":${PATH}:" in
  *":${VENV_DIR}/bin:"*) ;;
  *) export PATH="${VENV_DIR}/bin:${PATH}" ;;
esac

boot_log() {
  level="$1"
  step="$2"
  message="$3"
  printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
}

mask_env() {
  env | sort | while IFS='=' read -r key value; do
    case "$key" in
      *TOKEN*|*PASSWORD*|*SECRET*|*KEY*)
        printf '%s=%s\n' "$key" '***MASKED***'
        ;;
      *)
        printf '%s=%s\n' "$key" "$value"
        ;;
    esac
  done
}

remaining_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-boot-fragments)
      XFORCE_SOURCE_BOOT_FRAGMENTS=0
      shift
      ;;
    --debug-boot)
      XFORCE_DEBUG_BOOT=1
      shift
      ;;
    --print-env)
      XFORCE_PRINT_ENV=1
      shift
      ;;
    --skip-ready-marker)
      XFORCE_SKIP_READY_MARKER=1
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        remaining_args+=("$1")
        shift
      done
      ;;
    *)
      remaining_args+=("$1")
      shift
      ;;
  esac
done

export XFORCE_SKIP_READY_MARKER XFORCE_DEBUG_BOOT XFORCE_PRINT_ENV XFORCE_SOURCE_BOOT_FRAGMENTS

if [ "$XFORCE_DEBUG_BOOT" = "1" ]; then
  set -x
fi

boot_log info default "started_at=${XFORCE_BOOT_STARTED_AT}"

if [ "$XFORCE_PRINT_ENV" = "1" ]; then
  mask_env >&2
fi

if [ "$XFORCE_SOURCE_BOOT_FRAGMENTS" = "1" ]; then
  if [ ! -d "$XFORCE_BOOT_DIR" ]; then
    boot_log error fragments "boot fragment directory missing"
    exit 1
  fi

  found_fragment=0
  for script in "$XFORCE_BOOT_DIR"/*.sh; do
    [ -e "$script" ] || continue
    [ -f "$script" ] || continue
    if [ ! -r "$script" ]; then
      boot_log warn fragments "skipping unreadable script=$(basename "$script")"
      continue
    fi
    found_fragment=1
    boot_log info fragment "sourcing script=$(basename "$script")"
    # shellcheck disable=SC1090
    . "$script"
  done

  if [ "$found_fragment" = "0" ]; then
    boot_log warn fragments "no fragments found"
  fi
else
  boot_log info fragments "skipped"
fi

boot_log info default "complete"

if [ "${#remaining_args[@]}" -gt 0 ]; then
  boot_log info exec "command=${remaining_args[0]}"
  exec "${remaining_args[@]}"
fi

boot_log info exec "command=${SHELL:-/bin/bash}"
exec "${SHELL:-/bin/bash}" -l
