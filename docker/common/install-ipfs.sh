#!/usr/bin/env bash
set -Eeuo pipefail

version="${KUBO_VERSION:?KUBO_VERSION is required}"
version="${version#v}"
target_arch="${TARGETARCH:-}"
install_path="${KUBO_INSTALL_PATH:-/usr/local/bin/ipfs}"

if [ -z "$target_arch" ]; then
  case "$(dpkg --print-architecture)" in
    amd64) target_arch=amd64 ;;
    arm64) target_arch=arm64 ;;
    *)
      echo "unsupported dpkg architecture for Kubo: $(dpkg --print-architecture)" >&2
      exit 1
      ;;
  esac
fi

case "$target_arch" in
  amd64 | arm64)
    expected_sha512="$(eval "printf '%s' \"\${KUBO_SHA512_${target_arch^^}:-}\"")"
    ;;
  *)
    echo "unsupported TARGETARCH for Kubo: $target_arch" >&2
    exit 1
    ;;
esac

if [ -z "$expected_sha512" ]; then
  echo "missing required Kubo SHA512 for TARGETARCH=$target_arch" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

asset="kubo_v${version}_linux-${target_arch}.tar.gz"
url="https://dist.ipfs.tech/kubo/v${version}/${asset}"
archive="$tmp_dir/$asset"
extract_dir="$tmp_dir/extract"

mkdir -p "$extract_dir" "$(dirname "$install_path")"
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$archive" "$url"
printf '%s  %s\n' "$expected_sha512" "$archive" | sha512sum -c -
tar -xzf "$archive" -C "$extract_dir"

ipfs_bin="$(find "$extract_dir" -type f -path '*/ipfs' -perm /111 | head -n 1)"
if [ -z "$ipfs_bin" ]; then
  echo "ipfs executable not found in $asset" >&2
  exit 1
fi

install -m 0755 "$ipfs_bin" "$install_path"
"$install_path" version
