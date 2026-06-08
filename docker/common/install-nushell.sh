#!/usr/bin/env bash
set -Eeuo pipefail

version="${NUSHELL_VERSION:?NUSHELL_VERSION is required}"
target_arch="${TARGETARCH:-}"
sha256_amd64="${NUSHELL_SHA256_AMD64:-}"
sha256_arm64="${NUSHELL_SHA256_ARM64:-}"
install_path="${NUSHELL_INSTALL_PATH:-/usr/local/bin/nu}"

if [ -z "$target_arch" ]; then
  case "$(dpkg --print-architecture)" in
    amd64) target_arch=amd64 ;;
    arm64) target_arch=arm64 ;;
    *)
      echo "unsupported dpkg architecture for Nushell: $(dpkg --print-architecture)" >&2
      exit 1
      ;;
  esac
fi

case "$target_arch" in
  amd64)
    target_triple="x86_64-unknown-linux-gnu"
    expected_sha256="$sha256_amd64"
    ;;
  arm64)
    target_triple="aarch64-unknown-linux-gnu"
    expected_sha256="$sha256_arm64"
    ;;
  *)
    echo "unsupported TARGETARCH for Nushell: $target_arch" >&2
    exit 1
    ;;
esac

if [ -z "$expected_sha256" ]; then
  echo "missing required Nushell SHA256 for TARGETARCH=$target_arch" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

asset="nu-${version}-${target_triple}.tar.gz"
url="https://github.com/nushell/nushell/releases/download/${version}/${asset}"
archive="$tmp_dir/$asset"
extract_dir="$tmp_dir/extract"

mkdir -p "$extract_dir"
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$archive" "$url"
printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$extract_dir"

nu_bin="$(find "$extract_dir" -type f -name nu -perm /111 | head -n 1)"
if [ -z "$nu_bin" ]; then
  echo "Nushell executable not found in $asset" >&2
  exit 1
fi

install -m 0755 "$nu_bin" "$install_path"
"$install_path" --version >/dev/null
