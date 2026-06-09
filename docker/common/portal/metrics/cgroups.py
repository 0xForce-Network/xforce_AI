from __future__ import annotations

from pathlib import Path


def detect_version(root: Path) -> str:
    return "v2" if (root / "cgroup.controllers").exists() else "v1"


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def read_int(path: Path) -> int | None:
    value = read_text(path)
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def parse_key_value_file(path: Path) -> dict[str, int]:
    data: dict[str, int] = {}
    text = read_text(path)
    if not text:
        return data
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            data[parts[0]] = int(parts[1])
        except ValueError:
            continue
    return data


def first_existing(root: Path, candidates: list[str]) -> Path | None:
    for item in candidates:
        path = root / item
        if path.exists():
            return path
    return None
