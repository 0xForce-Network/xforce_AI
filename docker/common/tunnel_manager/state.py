from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from caddy_manager.auth import mask_secret


def masked_command(command: list[str], secret: str | None = None) -> list[str]:
    if not secret:
        return command
    return ["***MASKED***" if item == secret else item for item in command]


def write_state(state_dir: Path, payload: dict[str, Any]) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "state.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = []
    for key, value in sorted(payload.items()):
        if isinstance(value, (str, int, float, bool)) or value is None:
            lines.append(f"XFORCE_TUNNEL_{key.upper()}={value if value is not None else ''}")
    (state_dir / "tunnel.env").write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_state(state_dir: Path) -> dict[str, Any]:
    path = state_dir / "state.json"
    if not path.exists():
        return {"status": "missing"}
    return json.loads(path.read_text(encoding="utf-8"))
