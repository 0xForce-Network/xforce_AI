from __future__ import annotations

from pathlib import Path
from typing import Any

from .config import load_data


def inspect_report(path: Path) -> dict[str, Any]:
    return load_data(path)
