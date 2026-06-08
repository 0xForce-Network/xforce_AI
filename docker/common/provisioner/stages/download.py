from __future__ import annotations

import json
import os
import shutil
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from ..locks import DirectoryLock
from ..retry import RetryableError, run_with_retry
from ..state import ProvisionContext, safe_key, sha256_file, utc_now


def _copy_url(url: str, partial: Path) -> None:
    parsed = urlparse(url)
    try:
        if parsed.scheme == "file":
            shutil.copyfile(Path(parsed.path), partial)
        elif parsed.scheme in {"http", "https"}:
            with urllib.request.urlopen(url, timeout=60) as response, partial.open("wb") as handle:
                shutil.copyfileobj(response, handle)
        else:
            shutil.copyfile(Path(url), partial)
    except Exception as exc:  # noqa: BLE001
        raise RetryableError(f"download failed: {url}") from exc


def _dest(ctx: ProvisionContext, stage: dict[str, Any]) -> Path:
    if stage.get("dest"):
        return Path(stage["dest"])
    return ctx.workspace_dir / "models" / str(stage["filename"])


def run_download_stage(ctx: ProvisionContext, stage: dict[str, Any]) -> list[str]:
    url = str(stage["url"])
    dest = _dest(ctx, stage)
    expected = stage.get("sha256")
    lock = ctx.state_dir / "locks" / f"download-{safe_key(str(dest))}.lock"
    if ctx.dry_run:
        return [f"download:{url}->{dest}"]
    with DirectoryLock(lock):
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists() and expected and sha256_file(dest) == expected:
            return [f"download:skip:{dest}"]
        if dest.exists() and expected and sha256_file(dest) != expected and not stage.get("overwrite"):
            raise ValueError(f"existing destination checksum mismatch: {dest}")
        partial = dest.with_name(dest.name + ".partial")
        run_with_retry(lambda: _copy_url(url, partial), retries=0 if ctx.no_retry else int(stage.get("retries", ctx.max_retries)), base_seconds=ctx.backoff_base_seconds, max_seconds=ctx.backoff_max_seconds)
        if expected and sha256_file(partial) != expected:
            partial.unlink(missing_ok=True)
            raise ValueError(f"checksum mismatch for {dest}")
        partial.replace(dest)
        if stage.get("mode"):
            os.chmod(dest, int(str(stage["mode"]), 8))
    return [f"download:{dest}"]


def run_model_stage(ctx: ProvisionContext, stage: dict[str, Any]) -> list[str]:
    outputs = run_download_stage(ctx, stage)
    dest = _dest(ctx, stage)
    registry = ctx.state_dir / "models.json"
    models: list[dict[str, Any]] = []
    if registry.exists():
        models = json.loads(registry.read_text(encoding="utf-8"))
    record = {
        "stageId": stage["id"],
        "path": str(dest),
        "format": stage.get("format", ""),
        "tags": stage.get("tags", []),
        "sha256": stage.get("sha256", ""),
        "updatedAt": utc_now(),
    }
    models = [item for item in models if item.get("stageId") != stage["id"]]
    models.append(record)
    registry.write_text(json.dumps(models, indent=2, sort_keys=True), encoding="utf-8")
    return outputs + ["model:" + str(dest)]
