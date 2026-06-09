from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any

from .config import utc_now, write_json


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def publish_local(report: dict[str, Any], artifact_dir: Path) -> dict[str, Any]:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    report_id = str(report["report_id"])
    artifact_path = artifact_dir / f"{report_id}-fixture-artifact.txt"
    artifact_path.write_text(f"fixture artifact for {report_id}\n", encoding="utf-8")
    checksum = sha256_file(artifact_path)
    metadata = {
        "artifact_id": f"hil-artifact-{checksum.split(':', 1)[1][:16]}",
        "artifact_type": "fixture",
        "name": artifact_path.name,
        "report_id": report_id,
        "checksum": checksum,
        "location": f"local://{artifact_path}",
        "created_at": utc_now(),
    }
    write_json(artifact_dir / f"{metadata['artifact_id']}.json", metadata)
    return metadata
