#!/usr/bin/env bash

xforce_cuda_log() {
  level="$1"
  step="$2"
  message="$3"
  if command -v boot_log >/dev/null 2>&1; then
    boot_log "$level" "$step" "$message"
  else
    printf '[xforce-boot] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
  fi
}

xforce_cuda_state_dir="${XFORCE_CUDA_STATE_DIR:-${XFORCE_BOOT_STATE_DIR:-/tmp/xforce-ai}}"
xforce_cuda_state_file="${xforce_cuda_state_dir}/cuda-adaptation.env"
xforce_gpu_state_file="${xforce_cuda_state_dir}/gpu-adaptation.env"
xforce_cuda_root="${XFORCE_CUDA_ROOT:-/usr/local}"
xforce_cuda_symlink="${XFORCE_CUDA_SYMLINK:-${xforce_cuda_root}/cuda}"
xforce_ldconfig_bin="${XFORCE_LDCONFIG_BIN:-ldconfig}"
xforce_ldconfig_dir="${XFORCE_LDCONF_DIR:-/etc/ld.so.conf.d}"
xforce_nvidia_smi_bin="${XFORCE_NVIDIA_SMI_BIN:-nvidia-smi}"

xforce_cuda_write_state() {
  status="$1"
  selected="${2:-}"
  driver_max="${3:-}"
  forward_compat="${4:-0}"
  mkdir -p "$xforce_cuda_state_dir"
  {
    printf 'XFORCE_CUDA_STATUS=%s\n' "$status"
    printf 'XFORCE_CUDA_SELECTED_VERSION=%s\n' "$selected"
    printf 'XFORCE_CUDA_DRIVER_MAX_VERSION=%s\n' "$driver_max"
    printf 'XFORCE_CUDA_FORWARD_COMPAT=%s\n' "$forward_compat"
  } > "$xforce_cuda_state_file"
}

xforce_cuda_read_state_value() {
  file="$1"
  key="$2"
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | tail -n 1 | cut -d= -f2-
}

xforce_cuda_write_gpu_summary() {
  cuda_status="$(xforce_cuda_read_state_value "$xforce_cuda_state_file" XFORCE_CUDA_STATUS)"
  rocm_state_file="${xforce_cuda_state_dir}/rocm-adaptation.env"
  rocm_status="$(xforce_cuda_read_state_value "$rocm_state_file" XFORCE_ROCM_STATUS)"
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
  mkdir -p "$xforce_cuda_state_dir"
  {
    printf 'XFORCE_GPU_VENDOR=%s\n' "$vendor"
    printf 'XFORCE_CUDA_STATUS=%s\n' "${cuda_status:-skipped}"
    printf 'XFORCE_ROCM_STATUS=%s\n' "${rocm_status:-skipped}"
  } > "$xforce_gpu_state_file"
  xforce_cuda_log info gpu "vendor=${vendor}"
}

xforce_cuda_command_exists() {
  command_name="$1"
  case "$command_name" in
    */*) [ -x "$command_name" ] ;;
    *) command -v "$command_name" >/dev/null 2>&1 ;;
  esac
}

xforce_cuda_smi() {
  "$xforce_nvidia_smi_bin" "$@"
}

xforce_cuda_version_key() {
  version="$1"
  major="${version%%.*}"
  rest="${version#*.}"
  minor="${rest%%.*}"
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
  printf '%04d%04d\n' "$major" "$minor"
}

xforce_cuda_version_mm() {
  version="$1"
  major="${version%%.*}"
  rest="${version#*.}"
  minor="${rest%%.*}"
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s.%s\n' "$major" "$minor"
}

xforce_cuda_version_le() {
  left_key="$(xforce_cuda_version_key "$1")"
  right_key="$(xforce_cuda_version_key "$2")"
  [ "$left_key" -le "$right_key" ]
}

xforce_cuda_version_gt() {
  left_key="$(xforce_cuda_version_key "$1")"
  right_key="$(xforce_cuda_version_key "$2")"
  [ "$left_key" -gt "$right_key" ]
}

xforce_cuda_run_ldconfig() {
  [ "${XFORCE_SKIP_LDCONFIG:-0}" = "1" ] && return 0
  xforce_cuda_command_exists "$xforce_ldconfig_bin" || return 0
  "$xforce_ldconfig_bin"
}

xforce_cuda_probe_forward_compat() {
  compat_dir="$1"
  case "${XFORCE_CUDA_FORWARD_COMPAT_PROBE:-}" in
    pass) return 0 ;;
    fail|skip) return 1 ;;
  esac
  command -v python3 >/dev/null 2>&1 || return 1
  LD_LIBRARY_PATH="$compat_dir" python3 - <<'PY' 2>/dev/null
import ctypes
import sys

try:
    cuda = ctypes.CDLL('libcuda.so.1')
    sys.exit(0 if cuda.cuInit(0) == 0 else 1)
except Exception:
    sys.exit(1)
PY
}

xforce_cuda_try_forward_compat() {
  latest_version="$1"
  latest_path="$2"
  driver_max="$3"
  [ "${XFORCE_DISABLE_CUDA_FORWARD_COMPAT:-false}" = "true" ] && return 1
  xforce_cuda_version_gt "$latest_version" "$driver_max" || return 1
  compat_dir="${latest_path}/compat"
  [ -d "$compat_dir" ] || return 1
  compgen -G "${compat_dir}/libcuda.so*" >/dev/null || return 1
  xforce_cuda_probe_forward_compat "$compat_dir" || return 1
  mkdir -p "$xforce_ldconfig_dir"
  printf '%s\n' "$compat_dir" > "${xforce_ldconfig_dir}/0-compat-cuda.conf"
  return 0
}

xforce_cuda_collect_candidates() {
  for dir in "${xforce_cuda_root}"/cuda-*; do
    [ -d "$dir" ] || continue
    base="$(basename "$dir")"
    raw_version="${base#cuda-}"
    version="$(xforce_cuda_version_mm "$raw_version" 2>/dev/null || true)"
    [ -n "$version" ] || continue
    key="$(xforce_cuda_version_key "$version")"
    printf '%s|%s|%s\n' "$key" "$version" "$dir"
  done | sort -t '|' -k1,1nr
}

xforce_configure_cuda() {
  if ! xforce_cuda_command_exists "$xforce_nvidia_smi_bin"; then
    xforce_cuda_write_state skipped "" "" 0
    xforce_cuda_write_gpu_summary
    xforce_cuda_log info cuda "status=skipped reason=nvidia_smi_missing"
    return 0
  fi

  smi_output="$(xforce_cuda_smi 2>/dev/null || true)"
  driver_max="$(printf '%s\n' "$smi_output" | sed -n 's/.*CUDA Version: \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
  if [ -z "$driver_max" ]; then
    xforce_cuda_write_state skipped "" "" 0
    xforce_cuda_write_gpu_summary
    xforce_cuda_log info cuda "status=skipped reason=no_cuda_driver_signal"
    return 0
  fi

  gpu_name="$(xforce_cuda_smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || true)"
  compute_cap="$(xforce_cuda_smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n 1 || true)"
  driver_version="$(xforce_cuda_smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n 1 || true)"

  candidates="$(xforce_cuda_collect_candidates)"
  if [ -z "$candidates" ]; then
    xforce_cuda_write_state no_toolkit "" "$driver_max" 0
    xforce_cuda_write_gpu_summary
    xforce_cuda_log warn cuda "status=no_toolkit driver_max=${driver_max}"
    return 0
  fi

  latest_line="$(printf '%s\n' "$candidates" | head -n 1)"
  IFS='|' read -r _latest_key latest_version latest_path <<EOF
$latest_line
EOF

  selected_version=""
  selected_path=""
  forward_compat=0
  status=selected

  if xforce_cuda_try_forward_compat "$latest_version" "$latest_path" "$driver_max"; then
    selected_version="$latest_version"
    selected_path="$latest_path"
    forward_compat=1
    status=forward_compat
  fi

  if [ -z "$selected_version" ]; then
    while IFS='|' read -r _key version path; do
      [ -n "$version" ] || continue
      if xforce_cuda_version_le "$version" "$driver_max"; then
        selected_version="$version"
        selected_path="$path"
        break
      fi
    done <<EOF
$candidates
EOF
  fi

  if [ -z "$selected_version" ]; then
    last_line="$(printf '%s\n' "$candidates" | tail -n 1)"
    IFS='|' read -r _last_key selected_version selected_path <<EOF
$last_line
EOF
    status=selected
    xforce_cuda_log warn cuda "status=degraded reason=no_driver_compatible_toolkit selected=${selected_version} driver_max=${driver_max}"
  fi

  rm -f "${xforce_ldconfig_dir}/10-cuda.conf" "${xforce_ldconfig_dir}/10-xforce-cuda.conf" 2>/dev/null || true
  mkdir -p "$xforce_ldconfig_dir"
  if [ -L "$xforce_cuda_symlink" ] || [ -f "$xforce_cuda_symlink" ]; then
    rm -f "$xforce_cuda_symlink"
  elif [ -d "$xforce_cuda_symlink" ]; then
    current_cuda_target="$(readlink -f "$xforce_cuda_symlink" 2>/dev/null || true)"
    selected_cuda_target="$(readlink -f "$selected_path" 2>/dev/null || true)"
    if [ -n "$current_cuda_target" ] && [ "$current_cuda_target" = "$selected_cuda_target" ]; then
      xforce_cuda_log info cuda "status=symlink_unchanged target=${selected_path}"
    else
      xforce_cuda_write_state error "" "$driver_max" "$forward_compat"
      xforce_cuda_write_gpu_summary
      xforce_cuda_log error cuda "status=error reason=cuda_path_is_directory path=${xforce_cuda_symlink} selected=${selected_path}"
      return 1
    fi
  fi
  if [ ! -e "$xforce_cuda_symlink" ]; then
    ln -s "$selected_path" "$xforce_cuda_symlink"
  fi

  export CUDA_HOME="$xforce_cuda_symlink"
  case ":${PATH}:" in
    *":${CUDA_HOME}/bin:"*) ;;
    *) export PATH="${CUDA_HOME}/bin:${PATH}" ;;
  esac

  if [ -d "${CUDA_HOME}/lib64" ]; then
    printf '%s\n' "${CUDA_HOME}/lib64" > "${xforce_ldconfig_dir}/10-cuda.conf"
  fi
  xforce_cuda_run_ldconfig

  if [ -e /usr/lib/x86_64-linux-gnu/libcuda.so.1 ] && [ ! -e /usr/lib/x86_64-linux-gnu/libcuda.so ]; then
    ln -s /usr/lib/x86_64-linux-gnu/libcuda.so.1 /usr/lib/x86_64-linux-gnu/libcuda.so 2>/dev/null || true
  fi

  xforce_cuda_write_state "$status" "$selected_version" "$driver_max" "$forward_compat"
  xforce_cuda_write_gpu_summary
  xforce_cuda_log info cuda "status=${status} version=${selected_version} driver_max=${driver_max} forward_compat=${forward_compat} gpu=${gpu_name:-unknown} cc=${compute_cap:-unknown} driver=${driver_version:-unknown}"
}

xforce_configure_cuda
