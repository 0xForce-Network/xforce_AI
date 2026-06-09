#!/usr/bin/env bash
set -Eeuo pipefail

metadata_dir="${METADATA_DIR:-dist/metadata}"
output="${OUTPUT:-dist/xforce-ai-digests-${RELEASE_TAG:-dev}.json}"
release_tag="${RELEASE_TAG:-${IMAGE_TAG:-dev}}"
commit="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || printf unknown)}"

mkdir -p "$(dirname "$output")"

python3 - "$metadata_dir" "$output" "$release_tag" "$commit" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path

metadata_dir = Path(sys.argv[1])
output = Path(sys.argv[2])
release_tag = sys.argv[3]
commit = sys.argv[4]

images = []
for path in sorted(metadata_dir.glob("*.json")):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        continue
    digest = data.get("containerimage.digest") or data.get("digest") or ""
    tags = data.get("image.name") or data.get("tags") or []
    if isinstance(tags, str):
        tags = [item.strip() for item in tags.split(",") if item.strip()]
    variant = path.stem.split("-")[0]
    for tag in tags or [""]:
        repository, _, image_tag = tag.partition(":")
        registry = "dockerhub" if repository.startswith("docker.io/") else "ghcr" if repository.startswith("ghcr.io/") else "unknown"
        images.append(
            {
                "variant": variant,
                "registry": registry,
                "repository": repository,
                "tag": image_tag,
                "digest": digest,
                "platforms": data.get("platforms", []),
                "metadataFile": str(path),
            }
        )

payload = {
    "apiVersion": "xforce.ai/release-digests/v1",
    "tag": release_tag,
    "commit": commit,
    "generatedAt": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "images": images,
}
output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(output)
PY
