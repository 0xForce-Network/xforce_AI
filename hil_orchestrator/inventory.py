from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from typing import Any

from .states import CERTIFIED_ACTIVE, CERTIFIED_DEGRADED


def _parse_time(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


@dataclass(frozen=True)
class InventoryCandidate:
    node_id: str
    device_fingerprint: str
    device_index: int
    gpu_model: str
    vendor_id: str
    vram_gb: float
    compute_capability: float | None
    runtime: dict[str, Any]
    features: dict[str, bool]
    certification: dict[str, Any]
    node: dict[str, Any]

    @property
    def price_per_hour(self) -> float:
        return float(self.node.get("price_per_hour") or 0)

    @property
    def reputation_score(self) -> float:
        return float(self.node.get("reputation_score") or 0)

    @property
    def state(self) -> str:
        return str(self.certification.get("state") or self.node.get("status") or "Unverified")

    @property
    def vendor(self) -> str:
        vendor = self.vendor_id.lower()
        if vendor == "10de" or "nvidia" in self.gpu_model.lower():
            return "nvidia"
        if vendor == "1002" or "amd" in self.gpu_model.lower() or "radeon" in self.gpu_model.lower():
            return "rocm"
        return vendor

    def certification_expired(self, now: dt.datetime | None = None) -> bool:
        expires = _parse_time(str(self.certification.get("expires_at") or ""))
        if not expires:
            return False
        return expires <= (now or dt.datetime.now(dt.UTC))


def load_inventory(data: dict[str, Any]) -> list[InventoryCandidate]:
    candidates: list[InventoryCandidate] = []
    for node in data.get("nodes", []):
        for device in node.get("devices", []):
            candidates.append(
                InventoryCandidate(
                    node_id=str(node.get("node_id")),
                    device_fingerprint=str(device.get("device_fingerprint")),
                    device_index=int(device.get("device_index") or 0),
                    gpu_model=str(device.get("gpu_model")),
                    vendor_id=str(device.get("vendor_id") or ""),
                    vram_gb=float(device.get("vram_gb") or 0),
                    compute_capability=float(device["compute_capability"]) if device.get("compute_capability") is not None else None,
                    runtime=dict(device.get("runtime") or {}),
                    features=dict(device.get("features") or {}),
                    certification=dict(device.get("certification") or {}),
                    node=dict(node),
                )
            )
    return candidates


def eligible_state(candidate: InventoryCandidate, allow_degraded: bool = False) -> bool:
    if candidate.state == CERTIFIED_ACTIVE:
        return True
    return allow_degraded and candidate.state == CERTIFIED_DEGRADED
