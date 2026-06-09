from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import load_data, write_json


def write_lease(state_dir: Path, lease: dict[str, Any]) -> Path:
    lease_id = str(lease["lease_id"])
    path = state_dir / f"{lease_id}.json"
    write_json(path, lease)
    return path


def read_lease(state_dir: Path, lease_id: str) -> dict[str, Any]:
    return load_data(state_dir / f"{lease_id}.json")
