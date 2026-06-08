#!/usr/bin/env bash

xforce_rocm_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_rocm_state_dir="${XFORCE_ROCM_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
xforce_rocm_state_file="${xforce_rocm_state_dir}/rocm-adaptation.env"
xforce_gpu_state_file="${xforce_rocm_state_dir}/gpu-adaptation.env"
xforce_rocm_root="${XFORCE_ROCM_ROOT:-/opt/rocm}"
xforce_rocm_smi_bin="${XFORCE_ROCM_SMI_BIN:-rocm-smi}"
xforce_ldconfig_bin="${XFORCE_LDCONFIG_BIN:-ldconfig}"
xforce_ldconfig_dir="${XFORCE_LDCONF_DIR:-/etc/ld.so.conf.d}"

xforce_rocm_command_exists() {
  command_name="$1"
  case "$command_name" in
    */*) [ -x "$command_name" ] ;;
    *) command -v "$command_name" >/dev/null 2>&1 ;;
  esac
}

xforce_rocm_write_state() {
  status="$1"
  root_path="${2:-}"
  mkdir -p "$xforce_rocm_state_dir"
  {
    printf 'XFORCE_ROCM_STATUS=%s\n' "$status"
    printf 'XFORCE_ROCM_PATH=%s\n' "$root_path"
  } > "$xforce_rocm_state_file"
}

xforce_rocm_read_state_value() {
  file="$1"
  key="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

xforce_rocm_write_gpu_summary() {
  cuda_state_file="${xforce_rocm_state_dir}/cuda-adaptation.env"
  cuda_status="$(xforce_rocm_read_state_value "$cuda_state_file" XFORCE_CUDA_STATUS)"
  rocm_status="$(xforce_rocm_read_state_value "$xforce_rocm_state_file" XFORCE_ROCM_STATUS)"
  has_nvidia=0
  has_amd=0
  case "$cuda_status" in
    selected|forward_compat) has_nvidia=1 ;;
  esac
  case "$rocm_status" in
    detected|configured) has_amd=1 ;;
  esac
  vendor=none
  if [ "$has_nvidia" = "1" ] && [ "$has_amd" = "1" ]; then
    vendor=mixed
  elif [ "$has_nvidia" = "1" ]; then
    vendor=nvidia
  elif [ "$has_amd" = "1" ]; then
    vendor=amd
  fi
  mkdir -p "$xforce_rocm_state_dir"
  {
    printf 'XFORCE_GPU_VENDOR=%s\n' "$vendor"
    printf 'XFORCE_CUDA_STATUS=%s\n' "${cuda_status:-skipped}"
    printf 'XFORCE_ROCM_STATUS=%s\n' "${rocm_status:-skipped}"
  } > "$xforce_gpu_state_file"
  xforce_rocm_log info gpu "vendor=${vendor}"
}

xforce_rocm_run_ldconfig() {
  [ "${XFORCE_SKIP_LDCONFIG:-0}" = "1" ] && return 0
  xforce_rocm_command_exists "$xforce_ldconfig_bin" || return 0
  "$xforce_ldconfig_bin"
}

xforce_rocm_detect_signal() {
  [ -d "$xforce_rocm_root" ] && return 0
  xforce_rocm_command_exists rocminfo && return 0
  xforce_rocm_command_exists "$xforce_rocm_smi_bin" && return 0
  [ -e /dev/kfd ] && return 0
  [ -d /dev/dri ] && return 0
  return 1
}

xforce_configure_rocm() {
  if ! xforce_rocm_detect_signal; then
    xforce_rocm_write_state skipped ""
    xforce_rocm_write_gpu_summary
    xforce_rocm_log info rocm "status=skipped reason=no_rocm_signal"
    return 0
  fi

  if [ ! -d "$xforce_rocm_root" ]; then
    xforce_rocm_write_state detected ""
    xforce_rocm_write_gpu_summary
    xforce_rocm_log warn rocm "status=detected reason=rocm_root_missing root=${xforce_rocm_root}"
    return 0
  fi

  export ROCM_PATH="$xforce_rocm_root"
  export HIP_PATH="$xforce_rocm_root"
  export HIP_PLATFORM=amd

  if [ -d "${xforce_rocm_root}/bin" ]; then
    case ":${PATH}:" in
      *":${xforce_rocm_root}/bin:"*) ;;
      *) export PATH="${xforce_rocm_root}/bin:${PATH}" ;;
    esac
  fi

  rocm_ld_paths=""
  for lib_dir in "${xforce_rocm_root}/lib" "${xforce_rocm_root}/lib64"; do
    [ -d "$lib_dir" ] || continue
    rocm_ld_paths="${rocm_ld_paths}${lib_dir}\n"
    case ":${LD_LIBRARY_PATH:-}:" in
      *":${lib_dir}:"*) ;;
      *) export LD_LIBRARY_PATH="${lib_dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
    esac
  done

  mkdir -p "$xforce_ldconfig_dir"
  if [ -n "$rocm_ld_paths" ]; then
    printf '%b' "$rocm_ld_paths" > "${xforce_ldconfig_dir}/10-rocm.conf"
  fi
  xforce_rocm_run_ldconfig

  rocm_device_summary="unavailable"
  if xforce_rocm_command_exists "$xforce_rocm_smi_bin"; then
    rocm_device_summary="$($xforce_rocm_smi_bin --showproductname 2>/dev/null | head -n 1 || true)"
    [ -n "$rocm_device_summary" ] || rocm_device_summary="available"
  fi

  xforce_rocm_write_state configured "$xforce_rocm_root"
  xforce_rocm_write_gpu_summary
  xforce_rocm_log info rocm "status=configured root=${xforce_rocm_root} device=${rocm_device_summary}"
}

xforce_configure_rocm
