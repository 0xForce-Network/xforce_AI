#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build-image.sh <cpu|nvidia|rocm>

Environment variables:
  IMAGE_REGISTRY  default: ghcr.io/xforce-ai
  IMAGE_NAME      default: xforce-ai
  IMAGE_TAG       default: dev
  PLATFORMS       default: linux/amd64
  PUSH            default: 0
USAGE
}

variant="${1:-}"
if [ -z "$variant" ]; then
  usage >&2
  exit 2
fi

case "$variant" in
  cpu|nvidia|rocm) ;;
  *)
    usage >&2
    echo "unknown variant: $variant" >&2
    exit 2
    ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
dockerfile="${repo_root}/docker/${variant}/Dockerfile"

image_registry="${IMAGE_REGISTRY:-ghcr.io/xforce-ai}"
image_name="${IMAGE_NAME:-xforce-ai}"
image_tag="${IMAGE_TAG:-dev}"
platforms="${PLATFORMS:-linux/amd64}"
push="${PUSH:-0}"
full_tag="${image_registry}/${image_name}:${variant}-${image_tag}"

if [ ! -f "$dockerfile" ]; then
  echo "missing Dockerfile: $dockerfile" >&2
  exit 1
fi

build_args=(
  --build-arg "XFORCE_IMAGE_VERSION=${image_tag}"
)

for build_arg_name in ENABLE_NUSHELL NUSHELL_VERSION NUSHELL_SHA256_AMD64 NUSHELL_SHA256_ARM64; do
  build_arg_value="${!build_arg_name:-}"
  if [ -n "$build_arg_value" ]; then
    build_args+=(--build-arg "${build_arg_name}=${build_arg_value}")
  fi
done

cd "$repo_root"

if docker buildx version >/dev/null 2>&1; then
  cmd=(docker buildx build --platform "$platforms" -f "$dockerfile" -t "$full_tag" "${build_args[@]}")
  if [ "$push" = "1" ]; then
    cmd+=(--push)
  elif [[ "$platforms" != *,* ]]; then
    cmd+=(--load)
  fi
  cmd+=(.)
else
  if [ "$push" = "1" ]; then
    echo "PUSH=1 requires docker buildx" >&2
    exit 1
  fi
  cmd=(docker build -f "$dockerfile" -t "$full_tag" "${build_args[@]}" .)
fi

echo "+ ${cmd[*]}"
exec "${cmd[@]}"
