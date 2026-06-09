from __future__ import annotations

from typing import Any


def fixture_step(step: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": step.get("id"),
        "runner": step.get("runner"),
        "required": bool(step.get("required", True)),
        "status": str(step.get("fixture_status") or "passed"),
    }
