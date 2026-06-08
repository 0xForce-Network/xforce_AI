#!/usr/bin/env bash

export WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
export VENV_DIR="${VENV_DIR:-/venv/main}"
case ":${PATH}:" in
  *":${VENV_DIR}/bin:"*) ;;
  *) export PATH="${VENV_DIR}/bin:${PATH}" ;;
esac

mkdir -p "$XFORCE_BOOT_STATE_DIR" "$WORKSPACE_DIR"

boot_log info env "workspace=${WORKSPACE_DIR} venv=${VENV_DIR}"
