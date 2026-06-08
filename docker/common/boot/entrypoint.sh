#!/usr/bin/env bash
set -eu

XFORCE_BOOT_ROOT="${XFORCE_BOOT_ROOT:-/opt/xforce-ai}"
XFORCE_BOOT_DIR="${XFORCE_BOOT_DIR:-/etc/xforce_ai_boot.d}"
XFORCE_DEFAULT_BOOT="${XFORCE_DEFAULT_BOOT:-${XFORCE_BOOT_ROOT}/bin/boot_default.sh}"
XFORCE_CUSTOM_BOOT="${XFORCE_CUSTOM_BOOT:-${XFORCE_BOOT_ROOT}/bin/boot_custom.sh}"

boot_log() {
  level="$1"
  step="$2"
  message="$3"
  printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
}

normalize_script() {
  target="$1"
  if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$target" >/dev/null 2>&1 || true
  elif command -v perl >/dev/null 2>&1; then
    perl -pi -e 's/\r$//' "$target"
  elif command -v sed >/dev/null 2>&1; then
    sed -i 's/\r$//' "$target"
  fi
}

install_custom_boot() {
  source_ref="$1"
  tmp_target="${XFORCE_CUSTOM_BOOT}.tmp"
  mkdir -p "$(dirname "$XFORCE_CUSTOM_BOOT")"

  case "$source_ref" in
    http://*|https://*)
      boot_log info entrypoint "fetching custom boot script"
      curl -fsSL "$source_ref" -o "$tmp_target"
      ;;
    *)
      boot_log info entrypoint "copying custom boot script"
      if [ ! -f "$source_ref" ]; then
        boot_log error entrypoint "custom boot script path not found"
        exit 1
      fi
      cp "$source_ref" "$tmp_target"
      ;;
  esac

  normalize_script "$tmp_target"
  chmod 0755 "$tmp_target"
  mv "$tmp_target" "$XFORCE_CUSTOM_BOOT"
}

boot_log info entrypoint "starting"
boot_log info entrypoint "variant=${XFORCE_IMAGE_VARIANT:-unknown} version=${XFORCE_IMAGE_VERSION:-dev} workspace=${WORKSPACE_DIR:-/workspace} venv=${VENV_DIR:-/venv/main}"

if [ -n "${BOOT_SCRIPT:-}" ]; then
  install_custom_boot "$BOOT_SCRIPT"
fi

if [ -f "$XFORCE_CUSTOM_BOOT" ]; then
  if [ ! -x "$XFORCE_CUSTOM_BOOT" ]; then
    boot_log error entrypoint "custom boot script is not executable"
    exit 1
  fi
  boot_log info entrypoint "executing custom boot script"
  exec "$XFORCE_CUSTOM_BOOT" "$@"
fi

if [ ! -x "$XFORCE_DEFAULT_BOOT" ]; then
  boot_log error entrypoint "default boot script missing or not executable"
  exit 1
fi

boot_log info entrypoint "executing default boot script"
exec "$XFORCE_DEFAULT_BOOT" "$@"
