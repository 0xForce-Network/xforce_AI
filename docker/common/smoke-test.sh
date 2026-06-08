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
  /etc/xforce_ai_boot.d/20-workspace-sync.sh
  /etc/xforce_ai_boot.d/30-home-sync.sh
  /etc/xforce_ai_boot.d/40-venv-sync.sh
  /etc/xforce_ai_boot.d/99-ready.sh
  /opt/xforce-ai/share/workspace-seed
  /opt/xforce-ai/share/provisioner/examples/provisioning.example.yaml
  /opt/xforce-ai/lib/provisioner
  /opt/xforce-ai/bin/xforce-provision
  /opt/xforce-ai/bin/provisioner-smoke-test.sh
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

if [ ! -x /opt/xforce-ai/bin/xforce-provision ]; then
  echo "provisioner CLI is not executable" >&2
  exit 1
fi

if [ ! -x /opt/xforce-ai/bin/provisioner-smoke-test.sh ]; then
  echo "provisioner smoke test is not executable" >&2
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

if [ ! -f /tmp/xforce-ai/persistence.env ]; then
  echo "persistence summary missing" >&2
  exit 1
fi

grep -q '^XFORCE_SYNC_PERSISTENCE_STATUS=enabled' /tmp/xforce-ai/persistence.env
grep -q '^XFORCE_SYNC_WORKSPACE_STATUS=' /tmp/xforce-ai/persistence.env
grep -q '^XFORCE_SYNC_HOME_STATUS=synced' /tmp/xforce-ai/persistence.env
grep -q '^XFORCE_SYNC_VENV_STATUS=synced' /tmp/xforce-ai/persistence.env

if [ ! -f /tmp/xforce-ai/provisioner.env ]; then
  echo "provisioner summary missing" >&2
  exit 1
fi

grep -q '^XFORCE_PROVISION_STATUS=skipped' /tmp/xforce-ai/provisioner.env

if [ ! -d /workspace/.xforce-state ]; then
  echo "persistence state directory missing" >&2
  exit 1
fi

if [ ! -L /home/user ]; then
  echo "home sync did not link /home/user" >&2
  exit 1
fi

if [ ! -L /venv/main ]; then
  echo "venv sync did not link /venv/main" >&2
  exit 1
fi

run_nushell_smoke() {
  if [ "${ENABLE_NUSHELL:-1}" != "1" ]; then
    if [ -e /usr/local/bin/nu ]; then
      echo "Nushell binary exists while ENABLE_NUSHELL is disabled" >&2
      exit 1
    fi
    if getent passwd "${XFORCE_USER:-user}" | cut -d: -f7 | grep -qx /usr/local/bin/nu; then
      echo "user shell is Nushell while ENABLE_NUSHELL is disabled" >&2
      exit 1
    fi
    return 0
  fi

  if [ ! -x /usr/local/bin/nu ]; then
    echo "Nushell binary missing or not executable" >&2
    exit 1
  fi

  /usr/local/bin/nu --version | grep -q "${NUSHELL_VERSION:-0.113.1}"
  grep -qxF /usr/local/bin/nu /etc/shells

  user_shell="$(getent passwd "${XFORCE_USER:-user}" | cut -d: -f7)"
  if [ "$user_shell" != /usr/local/bin/nu ]; then
    echo "unexpected user shell: $user_shell" >&2
    exit 1
  fi

  nushell_config_dir="/home/${XFORCE_USER:-user}/.config/nushell"
  if [ ! -f "$nushell_config_dir/env.nu" ]; then
    echo "Nushell env config missing" >&2
    exit 1
  fi
  if [ ! -f "$nushell_config_dir/config.nu" ]; then
    echo "Nushell config missing" >&2
    exit 1
  fi

  /usr/local/bin/nu --no-std-lib --env-config "$nushell_config_dir/env.nu" --config "$nushell_config_dir/config.nu" -c 'if ($env.PATH.0 != "/venv/main/bin") { exit 1 }'
  /usr/local/bin/nu --no-std-lib --env-config "$nushell_config_dir/env.nu" --config "$nushell_config_dir/config.nu" -c 'show-models | ignore'
  /usr/local/bin/nu --no-std-lib --env-config "$nushell_config_dir/env.nu" --config "$nushell_config_dir/config.nu" -c 'call-llm "hello" | ignore'
}

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

run_workspace_fixture() {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/workspace" "$tmp/seed" "$tmp/state" "$tmp/boot-state"
  printf 'seed-new\n' > "$tmp/seed/new.txt"
  printf 'seed-existing\n' > "$tmp/seed/existing.txt"
  printf 'user-existing\n' > "$tmp/workspace/existing.txt"
  (
    export WORKSPACE_DIR="$tmp/workspace"
    export XFORCE_WORKSPACE_SEED_DIR="$tmp/seed"
    export XFORCE_PERSISTENCE_STATE_DIR="$tmp/state"
    export XFORCE_BOOT_STATE_DIR="$tmp/boot-state"
    export XFORCE_SYNC_PERSISTENCE=1
    export XFORCE_SYNC_WORKSPACE=1
    # shellcheck disable=SC1091
    . /etc/xforce_ai_boot.d/20-workspace-sync.sh
    grep -q '^XFORCE_SYNC_WORKSPACE_STATUS=synced' "$tmp/boot-state/workspace-sync.env"
    grep -q 'seed-new' "$tmp/workspace/new.txt"
    grep -q 'user-existing' "$tmp/workspace/existing.txt"
  )
  rm -rf "$tmp"
}

run_home_fixture() {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/workspace" "$tmp/home/user/.ssh" "$tmp/ssh" "$tmp/boot-state"
  printf 'hello\n' > "$tmp/home/user/profile.txt"
  printf 'ssh-key\n' > "$tmp/home/user/.ssh/authorized_keys"
  (
    export WORKSPACE_DIR="$tmp/workspace"
    export XFORCE_TEST_USER_HOME="$tmp/home/user"
    export XFORCE_CONTAINER_SSH_HOME="$tmp/ssh"
    export XFORCE_PERSISTENCE_STATE_DIR="$tmp/workspace/.xforce-state"
    export XFORCE_BOOT_STATE_DIR="$tmp/boot-state"
    export XFORCE_USER=user
    export XFORCE_UID="$(id -u)"
    export XFORCE_GID="$(id -g)"
    export XFORCE_SYNC_PERSISTENCE=1
    export XFORCE_SYNC_HOME=1
    # shellcheck disable=SC1091
    . /etc/xforce_ai_boot.d/30-home-sync.sh
    grep -q '^XFORCE_SYNC_HOME_STATUS=synced' "$tmp/boot-state/home-sync.env"
    [ -L "$tmp/home/user" ]
    grep -q 'hello' "$tmp/workspace/.xforce-state/home/user/profile.txt"
    [ -d "$tmp/ssh/user/.ssh" ]
    [ -L "$tmp/workspace/.xforce-state/home/user/.ssh" ]
  )
  rm -rf "$tmp"
}

run_venv_fixture() {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/workspace" "$tmp/venv/main/bin" "$tmp/boot-state"
  printf 'home = /usr\n' > "$tmp/venv/main/pyvenv.cfg"
  cat > "$tmp/venv/main/bin/python" <<'EOF_FAKE_PYTHON'
#!/usr/bin/env bash
printf 'py3.10\n'
EOF_FAKE_PYTHON
  chmod 0755 "$tmp/venv/main/bin/python"
  (
    export WORKSPACE_DIR="$tmp/workspace"
    export VENV_DIR="$tmp/venv/main"
    export XFORCE_PERSISTENCE_STATE_DIR="$tmp/workspace/.xforce-state"
    export XFORCE_BOOT_STATE_DIR="$tmp/boot-state"
    export XFORCE_IMAGE_VARIANT=fixture
    export XFORCE_IMAGE_VERSION=test
    export XFORCE_ENV_ID=fixture-env
    export XFORCE_SYNC_PERSISTENCE=1
    export XFORCE_SYNC_VENV=1
    # shellcheck disable=SC1091
    . /etc/xforce_ai_boot.d/40-venv-sync.sh
    grep -q '^XFORCE_SYNC_VENV_STATUS=synced' "$tmp/boot-state/venv-sync.env"
    [ -L "$tmp/venv/main" ]
    [ -f "$tmp/workspace/.xforce-state/environment/fixture-env/venv/main/pyvenv.cfg" ]
    # shellcheck disable=SC1091
    . /etc/xforce_ai_boot.d/40-venv-sync.sh
    [ -L "$tmp/venv/main" ]
  )
  rm -rf "$tmp"
}

run_cuda_fixture 12.4 12.4 fail
run_cuda_fixture 12.1 12.1 fail
run_cuda_fixture 12.1 12.8 pass
run_rocm_fixture
run_workspace_fixture
run_home_fixture
run_venv_fixture
run_nushell_smoke
/opt/xforce-ai/bin/provisioner-smoke-test.sh

python3 --version
/venv/main/bin/python --version
echo "xforce_AI F006 smoke test passed"
