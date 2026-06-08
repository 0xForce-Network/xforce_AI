from __future__ import annotations

import json
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

try:
    import yaml  # type: ignore[import-untyped]
except ModuleNotFoundError:  # pragma: no cover - fallback for host-side smoke before image deps exist
    yaml = None

from .retry import RetryableError, run_with_retry
from .state import ProvisionContext, sha256_text


SUPPORTED_STAGE_TYPES = {"apt", "pip", "git", "download", "model"}


class ManifestError(ValueError):
    pass


def is_url(value: str) -> bool:
    return value.startswith("http://") or value.startswith("https://")


def load_manifest(source: str, ctx: ProvisionContext) -> tuple[dict[str, Any], str]:
    if is_url(source):
        ctx.manifest_cache_dir.mkdir(parents=True, exist_ok=True)
        cache_path = ctx.manifest_cache_dir / f"{sha256_text(source)}.yaml"

        def fetch() -> bytes:
            try:
                with urllib.request.urlopen(source, timeout=30) as response:
                    return response.read()
            except Exception as exc:  # noqa: BLE001
                raise RetryableError(f"manifest fetch failed: {source}") from exc

        content = run_with_retry(
            fetch,
            retries=0 if ctx.no_retry else ctx.max_retries,
            base_seconds=ctx.backoff_base_seconds,
            max_seconds=ctx.backoff_max_seconds,
        )
        cache_path.write_bytes(content)
        (cache_path.with_suffix(".json")).write_text(json.dumps({"source": source, "sha256": sha256_text(content.decode("utf-8", errors="replace"))}, sort_keys=True), encoding="utf-8")
        text = content.decode("utf-8")
        manifest_source = "url"
    else:
        path = Path(source)
        text = path.read_text(encoding="utf-8")
        manifest_source = "local"

    try:
        manifest = safe_yaml_load(text)
    except Exception as exc:  # noqa: BLE001
        raise ManifestError(f"invalid YAML: {exc}") from exc
    if not isinstance(manifest, dict):
        raise ManifestError("manifest must be a mapping")
    validate_manifest(manifest)
    return manifest, manifest_source


def validate_manifest(manifest: dict[str, Any]) -> None:
    if manifest.get("apiVersion") != "xforce.ai/v1":
        raise ManifestError("apiVersion must be xforce.ai/v1")
    if manifest.get("kind") != "ProvisioningManifest":
        raise ManifestError("kind must be ProvisioningManifest")
    stages = manifest.get("stages")
    if not isinstance(stages, list) or not stages:
        raise ManifestError("stages must be a non-empty list")
    seen: set[str] = set()
    for stage in stages:
        if not isinstance(stage, dict):
            raise ManifestError("stage must be a mapping")
        stage_id = stage.get("id")
        stage_type = stage.get("type")
        if not isinstance(stage_id, str) or not stage_id:
            raise ManifestError("stage id is required")
        if stage_id in seen:
            raise ManifestError(f"duplicate stage id: {stage_id}")
        seen.add(stage_id)
        if stage_type not in SUPPORTED_STAGE_TYPES:
            raise ManifestError(f"unsupported stage type: {stage_type}")
        if stage_type == "apt" and not stage.get("packages"):
            raise ManifestError(f"apt stage {stage_id} requires packages")
        if stage_type == "pip" and not stage.get("packages") and not stage.get("requirements"):
            raise ManifestError(f"pip stage {stage_id} requires packages or requirements")
        if stage_type == "git" and (not stage.get("repo") or not stage.get("dest")):
            raise ManifestError(f"git stage {stage_id} requires repo and dest")
        if stage_type in {"download", "model"}:
            if not stage.get("url"):
                raise ManifestError(f"{stage_type} stage {stage_id} requires url")
            if not stage.get("dest") and not stage.get("filename"):
                raise ManifestError(f"{stage_type} stage {stage_id} requires dest or filename")
            parsed = urlparse(str(stage.get("url")))
            if parsed.scheme in {"http", "https"} and not stage.get("sha256") and not stage.get("allowUnverified"):
                raise ManifestError(f"{stage_type} stage {stage_id} requires sha256 for URL downloads")


def manifest_name(manifest: dict[str, Any], source: str) -> str:
    metadata = manifest.get("metadata") or {}
    if isinstance(metadata, dict) and metadata.get("name"):
        return str(metadata["name"])
    return sha256_text(source)[:16]


def safe_yaml_load(text: str) -> Any:
    if yaml is not None:
        return yaml.safe_load(text)
    return _fallback_yaml_load(text)


def _parse_scalar(value: str) -> Any:
    value = value.strip()
    if value == "":
        return ""
    if value in {"true", "True"}:
        return True
    if value in {"false", "False"}:
        return False
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [_parse_scalar(item.strip()) for item in inner.split(",")]
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    try:
        return int(value)
    except ValueError:
        return value


def _fallback_yaml_load(text: str) -> dict[str, Any]:
    """Small fallback parser for the simple F007 smoke manifests.

    Runtime images install PyYAML. This fallback keeps host-side smoke usable in
    minimal developer environments and intentionally supports only the subset
    used by our fixtures: nested mappings, list-of-mapping stages, and scalar
    lists.
    """
    result: dict[str, Any] = {}
    lines = [line.rstrip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    index = 0
    while index < len(lines):
        line = lines[index]
        if line.startswith(" "):
            index += 1
            continue
        key, _, raw = line.partition(":")
        key = key.strip()
        raw = raw.strip()
        if raw:
            result[key] = _parse_scalar(raw)
            index += 1
            continue
        if key == "stages":
            stages: list[dict[str, Any]] = []
            index += 1
            current: dict[str, Any] | None = None
            while index < len(lines):
                child = lines[index]
                if not child.startswith("  "):
                    break
                stripped = child.strip()
                if stripped.startswith("- "):
                    if current is not None:
                        stages.append(current)
                    current = {}
                    body = stripped[2:]
                    if body:
                        ckey, _, craw = body.partition(":")
                        current[ckey.strip()] = _parse_scalar(craw.strip())
                    index += 1
                    continue
                if current is None:
                    index += 1
                    continue
                ckey, _, craw = stripped.partition(":")
                ckey = ckey.strip()
                craw = craw.strip()
                if craw:
                    current[ckey] = _parse_scalar(craw)
                    index += 1
                    continue
                values: list[Any] = []
                index += 1
                while index < len(lines) and lines[index].startswith("      - "):
                    values.append(_parse_scalar(lines[index].strip()[2:]))
                    index += 1
                current[ckey] = values
            if current is not None:
                stages.append(current)
            result[key] = stages
            continue
        nested: dict[str, Any] = {}
        index += 1
        while index < len(lines) and lines[index].startswith("  "):
            stripped = lines[index].strip()
            nkey, _, nraw = stripped.partition(":")
            nested[nkey.strip()] = _parse_scalar(nraw.strip()) if nraw.strip() else {}
            index += 1
        result[key] = nested
    return result
