#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/image-tags.sh <cpu|nvidia|rocm> <tag-or-ref> [shortsha]

Environment variables:
  GHCR_REPOSITORY        default: ghcr.io/xforce-ai/xforce-ai
  DOCKERHUB_REPOSITORY   default: docker.io/xforce/xforce-ai
  INCLUDE_GHCR           default: 1
  INCLUDE_DOCKERHUB      default: 0
  INCLUDE_LATEST         default: 1 for release tags
  OUTPUT                 csv|lines|json, default: lines
USAGE
}

variant="${1:-}"
raw_tag="${2:-${IMAGE_TAG:-}}"
shortsha="${3:-${GITHUB_SHA:-}}"
shortsha="${shortsha:0:7}"

case "$variant" in
  cpu|nvidia|rocm) ;;
  *) usage >&2; echo "unknown variant: $variant" >&2; exit 2 ;;
esac

if [ -z "$raw_tag" ]; then
  usage >&2
  echo "missing tag" >&2
  exit 2
fi

strip_prefix="${raw_tag#refs/tags/}"
strip_prefix="${strip_prefix#xforce-ai/}"
release_tag="$strip_prefix"

is_release=0
if [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9._-]+)?$ ]]; then
  is_release=1
  normalized="$release_tag"
elif [[ "$release_tag" =~ ^[A-Za-z0-9._-]+$ && "$release_tag" != */* ]]; then
  normalized="$release_tag"
else
  safe_branch="$(printf '%s' "$release_tag" | tr -cs 'A-Za-z0-9_.-' '-' | sed -E 's/^-+|-+$//g; s/-+/-/g')"
  normalized="branch-${safe_branch:-unknown}"
fi

repos=()
if [ "${INCLUDE_GHCR:-1}" = "1" ]; then
  repos+=("${GHCR_REPOSITORY:-ghcr.io/xforce-ai/xforce-ai}")
fi
if [ "${INCLUDE_DOCKERHUB:-0}" = "1" ]; then
  repos+=("${DOCKERHUB_REPOSITORY:-docker.io/xforce/xforce-ai}")
fi

tags=()
for repo in "${repos[@]}"; do
  tags+=("${repo}:${variant}-${normalized}")
  if [ "$is_release" = "1" ] && [ "${INCLUDE_LATEST:-1}" = "1" ]; then
    tags+=("${repo}:${variant}-latest")
  fi
  if [ -n "$shortsha" ]; then
    tags+=("${repo}:${variant}-sha-${shortsha}")
  fi
done

case "${OUTPUT:-lines}" in
  csv)
    (IFS=','; printf '%s\n' "${tags[*]}")
    ;;
  json)
    python3 - "$variant" "$normalized" "${tags[@]}" <<'PY'
import json
import sys
variant = sys.argv[1]
tag = sys.argv[2]
tags = sys.argv[3:]
print(json.dumps({"variant": variant, "tag": tag, "tags": tags}, sort_keys=True))
PY
    ;;
  lines)
    printf '%s\n' "${tags[@]}"
    ;;
  *)
    echo "unsupported OUTPUT: ${OUTPUT}" >&2
    exit 2
    ;;
esac
