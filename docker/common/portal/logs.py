from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import PortalConfig
from .services import ServiceSpec, service_log_paths


def _is_relative_to(path: Path, base: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(base.resolve(strict=False))
        return True
    except ValueError:
        return False


def read_service_log(cfg: PortalConfig, spec: ServiceSpec, stream: str, offset: int, limit: int) -> dict[str, Any]:
    if offset < 0:
        offset = 0
    limit = max(0, min(limit, cfg.max_log_limit))
    paths = service_log_paths(cfg, spec)
    if stream not in paths:
        raise KeyError(stream)
    path = paths[stream]
    allowed_bases = [cfg.service_log_dir]
    if stream in {"ansi", "plain"}:
        allowed_bases.append(cfg.pty_log_dir)
    if not any(_is_relative_to(path, base) for base in allowed_bases):
        raise PermissionError("log path escaped allowed directories")
    if not path.exists():
        return {"serviceName": spec.name, "stream": stream, "offset": offset, "limit": limit, "nextOffset": offset, "eof": True, "content": ""}
    with path.open("rb") as fh:
        fh.seek(offset)
        data = fh.read(limit)
        next_offset = fh.tell()
        eof = not fh.read(1)
    return {
        "serviceName": spec.name,
        "stream": stream,
        "offset": offset,
        "limit": limit,
        "nextOffset": next_offset,
        "eof": eof,
        "content": data.decode("utf-8", errors="replace"),
    }
