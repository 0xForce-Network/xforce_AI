#!/usr/bin/env bash
set -Eeuo pipefail

required_paths=(
  /opt/xforce-ai/bin/entrypoint.sh
  /opt/xforce-ai/bin/boot_default.sh
  /opt/xforce-ai/lib
  /opt/portal-aio
  /etc/xforce_ai_boot.d
  /etc/xforce_ai_boot.d/00-env.sh
  /etc/xforce_ai_boot.d/05-nvidia-cuda.sh
  /etc/xforce_ai_boot.d/06-amd-rocm.sh
  /etc/xforce_ai_boot.d/99-ready.sh
  /etc/supervisor/conf.d
  /venv/main
  /workspace
  /home/user
)

for path in "${required_paths[@]}"; do
  if [ ! -e "$path" ]; then
    echo "missing required path: $path" >&2
    exit 1
  fi
done

if [ ! -x /opt/xforce-ai/bin/entrypoint.sh ]; then
  echo "entrypoint is not executable" >&2
  exit 1
fi

if [ ! -x /opt/xforce-ai/bin/boot_default.sh ]; then
  echo "default boot script is not executable" >&2
  exit 1
fi

if [ ! -f /tmp/xforce-ai/boot-ready ]; then
  echo "boot ready marker missing" >&2
  exit 1
fi

grep -q '^variant=' /tmp/xforce-ai/boot-ready
grep -q '^version=' /tmp/xforce-ai/boot-ready

if [ ! -f /tmp/xforce-ai/gpu-adaptation.env ]; then
  echo "gpu adaptation summary missing" >&2
  exit 1
fi

grep -q '^XFORCE_GPU_VENDOR=' /tmp/xforce-ai/gpu-adaptation.env
grep -q '^XFORCE_CUDA_STATUS=' /tmp/xforce-ai/gpu-adaptation.env
grep -q '^XFORCE_ROCM_STATUS=' /tmp/xforce-ai/gpu-adaptation.env

boot_log() {
  level="$1"
  step="$2"
  message="$3"
  printf '[xforce-smoke] level=%s step=%s message=%s\n' "$level" "$step" "$message" >&2
}

make_fake_ldconfig() {
  target="$1"
  cat > "$target" <<'EOF_LDCONFIG'
#!/usr/bin/env bash
printf 'ldconfig %s\n' "$*" >> "${XFORCE_FAKE_LDCONFIG_LOG:?}"
EOF_LDCONFIG
  chmod 0755 "$target"
}

make_fake_nvidia_smi() {
  target="$1"
  cat > "$target" <<'EOF_NVIDIA_SMI'
#!/usr/bin/env bash
case "$*" in
  *--query-gpu=name*)
    printf 'Fake NVIDIA GPU\n'
    ;;
  *--query-gpu=compute_cap*)
    printf '8.9\n'
    ;;
  *--query-gpu=driver_version*)
    printf '550.54.14\n'
    ;;
  *)
    printf 'NVIDIA-SMI 550.54.14    Driver Version: 550.54.14    CUDA Version: %s\n' "${XFORCE_FAKE_CUDA_MAX:-12.4}"
    ;;
esac
EOF_NVIDIA_SMI
  chmod 0755 "$target"
}

run_cuda_fixture() {
  max_cuda="$1"
  expected="$2"
  probe="${3:-}"
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/cuda-root/cuda-12.1/bin" "$tmp/cuda-root/cuda-12.1/lib64" "$tmp/cuda-root/cuda-12.4/bin" "$tmp/cuda-root/cuda-12.4/lib64" "$tmp/cuda-root/cuda-12.8/bin" "$tmp/cuda-root/cuda-12.8/lib64" "$tmp/cuda-root/cuda-12.8/compat" "$tmp/fake-bin" "$tmp/ld.so.conf.d" "$tmp/state"
  : > "$tmp/cuda-root/cuda-12.8/compat/libcuda.so.1"
  make_fake_nvidia_smi "$tmp/fake-bin/nvidia-smi"
  make_fake_ldconfig "$tmp/fake-bin/ldconfig"
  : > "$tmp/ldconfig.log"
  (
    export XFORCE_CUDA_ROOT="$tmp/cuda-root"
    export XFORCE_NVIDIA_SMI_BIN="$tmp/fake-bin/nvidia-smi"
    export XFORCE_LDCONFIG_BIN="$tmp/fake-bin/ldconfig"
    export XFORCE_LDCONF_DIR="$tmp/ld.so.conf.d"
    export XFORCE_CUDA_STATE_DIR="$tmp/state"
    export XFORCE_FAKE_LDCONFIG_LOG="$tmp/ldconfig.log"
    export XFORCE_FAKE_CUDA_MAX="$max_cuda"
    if [ -n "$probe" ]; then
      export XFORCE_CUDA_FORWARD_COMPAT_PROBE="$probe"
    fi
    # shellcheck disable=SC1091
    . /etc/xforce_ai_boot.d/05-nvidia-cuda.sh
    selected="$(grep '^XFORCE_CUDA_SELECTED_VERSION=' "$tmp/state/cuda-adaptation.env" | cut -d= -f2-)"
    if [ "$selected" != "$expected" ]; then
      echo "expected CUDA $expected, got $selected" >&2
      exit 1
    fi
    target="$(readlink "$tmp/cuda-root/cuda")"
    if [ "$target" != "$tmp/cuda-root/cuda-$expected" ]; then
      echo "unexpected CUDA symlink target: $target" >&2
      exit 1
    fi
    grep -q '^XFORCE_GPU_VENDOR=nvidia' "$tmp/state/gpu-adaptation.env"
    grep -q '^ldconfig' "$tmp/ldconfig.log"
  )
  rm -rf "$tmp"
}

run_rocm_fixture() {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/rocm-root/bin" "$tmp/rocm-root/lib" "$tmp/rocm-root/lib64" "$tmp/fake-bin" "$tmp/ld.so.conf.d" "$tmp/state"
  cat > "$tmp/rocm-root/bin/rocm-smi" <<'EOF_ROCM_SMI'
#!/usr/bin/env bash
printf 'Fake AMD GPU\n'
EOF_ROCM_SMI
  chmod 0755 "$tmp/rocm-root/bin/rocm-smi"
  make_fake_ldconfig "$tmp/fake-bin/ldconfig"
  : > "$tmp/ldconfig.log"
  (
    export XFORCE_ROCM_ROOT="$tmp/rocm-root"
    export XFORCE_ROCM_SMI_BIN="$tmp/rocm-root/bin/rocm-smi"
    export XFORCE_LDCONFIG_BIN="$tmp/fake-bin/ldconfig"
    export XFORCE_LDCONF_DIR="$tmp/ld.so.conf.d"
    export XFORCE_ROCM_STATE_DIR="$tmp/state"
    export XFORCE_FAKE_LDCONFIG_LOG="$tmp/ldconfig.log"
    # shellcheck disable=SC1091
    . /etc/xforce_ai_boot.d/06-amd-rocm.sh
    grep -q '^XFORCE_ROCM_STATUS=configured' "$tmp/state/rocm-adaptation.env"
    grep -q "^XFORCE_ROCM_PATH=$tmp/rocm-root" "$tmp/state/rocm-adaptation.env"
    grep -q '^XFORCE_GPU_VENDOR=amd' "$tmp/state/gpu-adaptation.env"
    [ "$ROCM_PATH" = "$tmp/rocm-root" ]
    [ "$HIP_PATH" = "$tmp/rocm-root" ]
    [ "$HIP_PLATFORM" = "amd" ]
    grep -q '^ldconfig' "$tmp/ldconfig.log"
  )
  rm -rf "$tmp"
}

run_cuda_fixture 12.4 12.4 fail
run_cuda_fixture 12.1 12.1 fail
run_cuda_fixture 12.1 12.8 pass
run_rocm_fixture

python3 --version
/venv/main/bin/python --version
echo "xforce_AI F004 smoke test passed"
