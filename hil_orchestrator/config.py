from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


def load_data(path: str | os.PathLike[str]) -> dict[str, Any]:
    text = Path(path).read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore[import-not-found]

        data = yaml.safe_load(text) or {}
        if isinstance(data, dict):
            return data
        raise ValueError(f"expected mapping in {path}")
    except ModuleNotFoundError:
        data = json.loads(text)
        if isinstance(data, dict):
            return data
        raise ValueError(f"expected mapping in {path}")


def write_json(path: str | os.PathLike[str], payload: dict[str, Any]) -> None:
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def utc_now() -> str:
    import datetime as dt

    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def env_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default))
