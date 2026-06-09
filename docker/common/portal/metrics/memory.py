from __future__ import annotations

from pathlib import Path
from typing import Any

from .cgroups import detect_version, first_existing, parse_key_value_file, read_int, read_text


UNLIMITED_V1_THRESHOLD = 1 << 60


def _limit(value: str | int | None, version: str) -> int | None:
    if value is None:
        return None
    if isinstance(value, str):
        if value == "max":
            return None
        try:
            value = int(value)
        except ValueError:
            return None
    if version == "v1" and value >= UNLIMITED_V1_THRESHOLD:
        return None
    return value


def read_memory_metrics(root: Path) -> dict[str, Any]:
    version = detect_version(root)
    if version == "v2":
        stat = parse_key_value_file(root / "memory.stat")
        limit_text = read_text(root / "memory.max")
        return {
            "version": "v2",
            "usageBytes": read_int(root / "memory.current") or 0,
            "limitBytes": _limit(limit_text, "v2"),
            "anonBytes": stat.get("anon", 0),
            "fileBytes": stat.get("file", 0),
            "kernelBytes": stat.get("kernel", 0),
        }

    usage_path = first_existing(root, ["memory.usage_in_bytes", "memory/memory.usage_in_bytes"])
    limit_path = first_existing(root, ["memory.limit_in_bytes", "memory/memory.limit_in_bytes"])
    stat_path = first_existing(root, ["memory.stat", "memory/memory.stat"])
    stat = parse_key_value_file(stat_path) if stat_path else {}
    raw_limit = read_int(limit_path) if limit_path else None
    return {
        "version": "v1",
        "usageBytes": read_int(usage_path) if usage_path else 0,
        "limitBytes": _limit(raw_limit, "v1"),
        "anonBytes": stat.get("total_rss", stat.get("rss", 0)),
        "fileBytes": stat.get("total_cache", stat.get("cache", 0)),
        "kernelBytes": stat.get("total_kernel_memory", stat.get("kernel_memory", 0)),
    }
