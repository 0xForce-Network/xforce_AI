#!/usr/bin/env bash
set -Eeuo pipefail

version="${CADDY_VERSION:?CADDY_VERSION is required}"
version="${version#v}"
target_arch="${TARGETARCH:-}"
sha512_amd64="${CADDY_SHA512_AMD64:-}"
sha512_arm64="${CADDY_SHA512_ARM64:-}"
install_path="${CADDY_INSTALL_PATH:-/usr/bin/caddy}"

if [ -z "$target_arch" ]; then
  case "$(dpkg --print-architecture)" in
    amd64) target_arch=amd64 ;;
    arm64) target_arch=arm64 ;;
    *)
      echo "unsupported dpkg architecture for Caddy: $(dpkg --print-architecture)" >&2
      exit 1
      ;;
  esac
fi

case "$target_arch" in
  amd64 | arm64)
    expected_sha512="$(eval "printf '%s' \"\${CADDY_SHA512_${target_arch^^}:-}\"")"
    ;;
  *)
    echo "unsupported TARGETARCH for Caddy: $target_arch" >&2
    exit 1
    ;;
esac

if [ -z "$expected_sha512" ]; then
  echo "missing required Caddy SHA512 for TARGETARCH=$target_arch" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

asset="caddy_${version}_linux_${target_arch}.tar.gz"
url="https://github.com/caddyserver/caddy/releases/download/v${version}/${asset}"
archive="$tmp_dir/$asset"
extract_dir="$tmp_dir/extract"

mkdir -p "$extract_dir" "$(dirname "$install_path")"
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$archive" "$url"
printf '%s  %s\n' "$expected_sha512" "$archive" | sha512sum -c -
tar -xzf "$archive" -C "$extract_dir"

caddy_bin="$(find "$extract_dir" -type f -name caddy -perm /111 | head -n 1)"
if [ -z "$caddy_bin" ]; then
  echo "Caddy executable not found in $asset" >&2
  exit 1
fi

install -m 0755 "$caddy_bin" "$install_path"
"$install_path" version
