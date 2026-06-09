#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build-image.sh <cpu|nvidia|rocm>

Environment variables:
  IMAGE_REGISTRY       default: ghcr.io/xforce-ai
  IMAGE_NAME           default: xforce-ai
  IMAGE_TAG            default: dev
  IMAGE_TAGS           comma-separated full image tags; overrides IMAGE_REGISTRY/IMAGE_NAME/IMAGE_TAG
  PLATFORMS            default: linux/amd64
  PUSH                 default: 0
  LOAD                 default: auto for single-platform no-push builds
  NO_CACHE             default: 0
  CACHE_FROM           optional buildx cache-from value
  CACHE_TO             optional buildx cache-to value
  OUTPUT_METADATA      optional buildx --metadata-file path
  BUILDX_BUILDER       optional buildx builder name
  DRY_RUN              print command without executing when set to 1
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
load="${LOAD:-auto}"
no_cache="${NO_CACHE:-0}"
dry_run="${DRY_RUN:-0}"

if [ ! -f "$dockerfile" ]; then
  echo "missing Dockerfile: $dockerfile" >&2
  exit 1
fi

tag_args=()
if [ -n "${IMAGE_TAGS:-}" ]; then
  IFS=',' read -r -a provided_tags <<< "$IMAGE_TAGS"
  for tag in "${provided_tags[@]}"; do
    tag="${tag//[[:space:]]/}"
    [ -n "$tag" ] || continue
    tag_args+=(-t "$tag")
  done
else
  tag_args=(-t "${image_registry}/${image_name}:${variant}-${image_tag}")
fi

if [ "${#tag_args[@]}" -eq 0 ]; then
  echo "no image tags resolved" >&2
  exit 1
fi

build_args=(--build-arg "XFORCE_IMAGE_VERSION=${image_tag}")
known_build_args=(
  ENABLE_NUSHELL
  ENABLE_PORTAL
  ENABLE_CLOUDFLARED
  NUSHELL_VERSION
  NUSHELL_SHA256_AMD64
  NUSHELL_SHA256_ARM64
  CLOUDFLARED_VERSION
  CLOUDFLARED_SHA256_AMD64
  CLOUDFLARED_SHA256_ARM64
  XFORCE_IMAGE_REVISION
  XFORCE_IMAGE_SOURCE
  XFORCE_IMAGE_CREATED
)

for build_arg_name in "${known_build_args[@]}"; do
  build_arg_value="${!build_arg_name:-}"
  if [ -n "$build_arg_value" ]; then
    build_args+=(--build-arg "${build_arg_name}=${build_arg_value}")
  fi
done

cd "$repo_root"

if docker buildx version >/dev/null 2>&1; then
  cmd=(docker buildx build --platform "$platforms")
  if [ -n "${BUILDX_BUILDER:-}" ]; then
    cmd+=(--builder "$BUILDX_BUILDER")
  fi
  cmd+=(-f "$dockerfile" "${tag_args[@]}" "${build_args[@]}")
  if [ "$push" = "1" ]; then
    cmd+=(--push)
  elif [ "$load" = "1" ] || { [ "$load" = auto ] && [[ "$platforms" != *,* ]]; }; then
    cmd+=(--load)
  fi
  if [ "$no_cache" = "1" ]; then
    cmd+=(--no-cache)
  fi
  if [ -n "${CACHE_FROM:-}" ]; then
    cmd+=(--cache-from "$CACHE_FROM")
  fi
  if [ -n "${CACHE_TO:-}" ]; then
    cmd+=(--cache-to "$CACHE_TO")
  fi
  if [ -n "${OUTPUT_METADATA:-}" ]; then
    mkdir -p "$(dirname "$OUTPUT_METADATA")"
    cmd+=(--metadata-file "$OUTPUT_METADATA")
  fi
  cmd+=(.)
else
  if [ "$push" = "1" ]; then
    echo "PUSH=1 requires docker buildx" >&2
    exit 1
  fi
  if [[ "$platforms" == *,* ]]; then
    echo "multi-platform builds require docker buildx" >&2
    exit 1
  fi
  cmd=(docker build -f "$dockerfile" "${tag_args[@]}" "${build_args[@]}")
  if [ "$no_cache" = "1" ]; then
    cmd+=(--no-cache)
  fi
  cmd+=(.)
fi

printf '+ '
printf '%q ' "${cmd[@]}"
printf '\n'

if [ "$dry_run" = "1" ]; then
  exit 0
fi

exec "${cmd[@]}"
