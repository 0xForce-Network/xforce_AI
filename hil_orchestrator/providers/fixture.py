from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any

from ..config import load_data, utc_now, write_json
from ..inventory import load_inventory


class FixtureProvider:
    def __init__(self, inventory_path: Path, state_dir: Path) -> None:
        self.inventory_path = inventory_path
        self.state_dir = state_dir

    def list_candidates(self, requirements: dict[str, Any]) -> list[dict[str, Any]]:
        candidates = load_inventory(load_data(self.inventory_path))
        min_vram = float(requirements.get("min_vram_gb") or 0)
        return [candidate.__dict__ for candidate in candidates if candidate.vram_gb >= min_vram]

    def acquire(self, candidate: dict[str, Any], lease_request: dict[str, Any]) -> dict[str, Any]:
        lease = {
            "lease_id": f"fixture-lease-{uuid.uuid4().hex[:12]}",
            "provider": "fixture",
            "status": "acquired",
            "candidate": candidate,
            "request": lease_request,
            "acquired_at": utc_now(),
        }
        write_json(self.state_dir / f"{lease['lease_id']}.json", lease)
        return lease

    def heartbeat(self, lease_id: str) -> dict[str, Any]:
        lease = self.describe(lease_id)
        lease["last_heartbeat_at"] = utc_now()
        write_json(self.state_dir / f"{lease_id}.json", lease)
        return lease

    def release(self, lease_id: str) -> dict[str, Any]:
        lease = self.describe(lease_id)
        lease["status"] = "released"
        lease["released_at"] = utc_now()
        write_json(self.state_dir / f"{lease_id}.json", lease)
        return lease

    def describe(self, lease_id: str) -> dict[str, Any]:
        return load_data(self.state_dir / f"{lease_id}.json")
