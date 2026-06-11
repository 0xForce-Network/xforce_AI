#!/usr/bin/env bash
set -Eeuo pipefail

# Shared deploy-time Docker resource profile helper for xforce_AI based app images.
# Source this file from deployment scripts, call xforce_apply_docker_resource_profile,
# then append flags/env with the xforce_append_* helpers.

XFORCE_DOCKER_RESOURCE_PROFILE="${XFORCE_DOCKER_RESOURCE_PROFILE:-${XFORCE_RESOURCE_PROFILE:-custom}}"
XFORCE_DOCKER_CPUS="${XFORCE_DOCKER_CPUS:-}"
XFORCE_DOCKER_CPUSET_CPUS="${XFORCE_DOCKER_CPUSET_CPUS:-}"
XFORCE_DOCKER_MEMORY="${XFORCE_DOCKER_MEMORY:-}"
XFORCE_DOCKER_MEMORY_SWAP="${XFORCE_DOCKER_MEMORY_SWAP:-}"
XFORCE_DOCKER_SHM_SIZE="${XFORCE_DOCKER_SHM_SIZE:-}"
XFORCE_DOCKER_PIDS_LIMIT="${XFORCE_DOCKER_PIDS_LIMIT:-}"
XFORCE_DOCKER_GPUS="${XFORCE_DOCKER_GPUS:-all}"
XFORCE_DOCKER_STORAGE_SIZE="${XFORCE_DOCKER_STORAGE_SIZE:-}"

xforce_apply_docker_resource_profile() {
  case "$XFORCE_DOCKER_RESOURCE_PROFILE" in
    custom|default|none|"")
      ;;
    gpu-small)
      : "${XFORCE_DOCKER_CPUS:=4}"
      : "${XFORCE_DOCKER_MEMORY:=16g}"
      : "${XFORCE_DOCKER_MEMORY_SWAP:=16g}"
      : "${XFORCE_DOCKER_SHM_SIZE:=4g}"
      : "${XFORCE_DOCKER_PIDS_LIMIT:=4096}"
      : "${XFORCE_DOCKER_GPUS:=all}"
      : "${XFORCE_DOCKER_STORAGE_SIZE:=80G}"
      ;;
    gpu-pro)
      : "${XFORCE_DOCKER_CPUS:=8}"
      : "${XFORCE_DOCKER_MEMORY:=32g}"
      : "${XFORCE_DOCKER_MEMORY_SWAP:=32g}"
      : "${XFORCE_DOCKER_SHM_SIZE:=8g}"
      : "${XFORCE_DOCKER_PIDS_LIMIT:=8192}"
      : "${XFORCE_DOCKER_GPUS:=all}"
      : "${XFORCE_DOCKER_STORAGE_SIZE:=160G}"
      ;;
    gpu-studio)
      : "${XFORCE_DOCKER_CPUS:=16}"
      : "${XFORCE_DOCKER_MEMORY:=64g}"
      : "${XFORCE_DOCKER_MEMORY_SWAP:=64g}"
      : "${XFORCE_DOCKER_SHM_SIZE:=16g}"
      : "${XFORCE_DOCKER_PIDS_LIMIT:=16384}"
      : "${XFORCE_DOCKER_GPUS:=all}"
      : "${XFORCE_DOCKER_STORAGE_SIZE:=320G}"
      ;;
    *)
      printf 'unsupported XFORCE_DOCKER_RESOURCE_PROFILE=%s; use custom, gpu-small, gpu-pro, or gpu-studio\n' "$XFORCE_DOCKER_RESOURCE_PROFILE" >&2
      return 2
      ;;
  esac
}

xforce_append_flag_if_set() {
  local array_name="$1"
  local flag="$2"
  local value="$3"
  if [ -n "$value" ]; then
    local -n target_array="$array_name"
    target_array+=("$flag" "$value")
  fi
}

xforce_append_docker_resource_flags() {
  local array_name="$1"
  local -n target_array="$array_name"
  if [ -n "${XFORCE_DOCKER_GPUS}" ]; then
    target_array+=(--gpus "${XFORCE_DOCKER_GPUS}")
  fi
  xforce_append_flag_if_set "$array_name" --cpus "${XFORCE_DOCKER_CPUS}"
  xforce_append_flag_if_set "$array_name" --cpuset-cpus "${XFORCE_DOCKER_CPUSET_CPUS}"
  xforce_append_flag_if_set "$array_name" --memory "${XFORCE_DOCKER_MEMORY}"
  xforce_append_flag_if_set "$array_name" --memory-swap "${XFORCE_DOCKER_MEMORY_SWAP}"
  xforce_append_flag_if_set "$array_name" --shm-size "${XFORCE_DOCKER_SHM_SIZE}"
  xforce_append_flag_if_set "$array_name" --pids-limit "${XFORCE_DOCKER_PIDS_LIMIT}"
  if [ -n "${XFORCE_DOCKER_STORAGE_SIZE}" ]; then
    target_array+=(--storage-opt "size=${XFORCE_DOCKER_STORAGE_SIZE}")
  fi
}

xforce_append_docker_resource_env() {
  local array_name="$1"
  local -n target_array="$array_name"
  target_array+=(
    -e "XFORCE_DOCKER_RESOURCE_PROFILE=${XFORCE_DOCKER_RESOURCE_PROFILE}"
    -e "XFORCE_DOCKER_CPUS=${XFORCE_DOCKER_CPUS}"
    -e "XFORCE_DOCKER_CPUSET_CPUS=${XFORCE_DOCKER_CPUSET_CPUS}"
    -e "XFORCE_DOCKER_MEMORY=${XFORCE_DOCKER_MEMORY}"
    -e "XFORCE_DOCKER_MEMORY_SWAP=${XFORCE_DOCKER_MEMORY_SWAP}"
    -e "XFORCE_DOCKER_SHM_SIZE=${XFORCE_DOCKER_SHM_SIZE}"
    -e "XFORCE_DOCKER_PIDS_LIMIT=${XFORCE_DOCKER_PIDS_LIMIT}"
    -e "XFORCE_DOCKER_GPUS=${XFORCE_DOCKER_GPUS}"
    -e "XFORCE_DOCKER_STORAGE_SIZE=${XFORCE_DOCKER_STORAGE_SIZE}"
  )
}

xforce_print_docker_resource_profile() {
  cat <<EOF
profile=${XFORCE_DOCKER_RESOURCE_PROFILE}
cpus=${XFORCE_DOCKER_CPUS:-default}
cpuset_cpus=${XFORCE_DOCKER_CPUSET_CPUS:-default}
memory=${XFORCE_DOCKER_MEMORY:-default}
memory_swap=${XFORCE_DOCKER_MEMORY_SWAP:-default}
shm_size=${XFORCE_DOCKER_SHM_SIZE:-default}
pids_limit=${XFORCE_DOCKER_PIDS_LIMIT:-default}
gpus=${XFORCE_DOCKER_GPUS:-default}
storage_size=${XFORCE_DOCKER_STORAGE_SIZE:-default}
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  xforce_apply_docker_resource_profile
  xforce_print_docker_resource_profile
fi
