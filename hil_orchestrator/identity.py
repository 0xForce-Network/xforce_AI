from __future__ import annotations

import hashlib
from typing import Any


def normalize_identity(device: dict[str, Any], node_id: str = "") -> dict[str, Any]:
    fingerprint = str(device.get("device_fingerprint") or "")
    if not fingerprint:
        material = "|".join(
            [
                node_id,
                str(device.get("device_index") or 0),
                str(device.get("vendor_id") or ""),
                str(device.get("device_id") or ""),
                str(device.get("gpu_uuid") or ""),
                str(device.get("pci_bus_id") or ""),
                str(device.get("gpu_model") or ""),
                str(device.get("vram_gb") or ""),
            ]
        )
        fingerprint = f"sha256:{hashlib.sha256(material.encode()).hexdigest()}"
    return {
        "node_id": node_id,
        "device_index": int(device.get("device_index") or 0),
        "vendor_id": str(device.get("vendor_id") or ""),
        "device_id": str(device.get("device_id") or ""),
        "uuid_source": str(device.get("uuid_source") or ""),
        "gpu_uuid": str(device.get("gpu_uuid") or ""),
        "device_fingerprint": fingerprint,
        "pci_bus_id": str(device.get("pci_bus_id") or ""),
        "gpu_model": str(device.get("gpu_model") or ""),
        "vram_gb": float(device.get("vram_gb") or 0),
    }
