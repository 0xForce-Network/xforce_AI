from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any


def _find_rocm_smi() -> str | None:
    override = os.environ.get("XFORCE_ROCM_SMI_BIN")
    if override:
        if "/" not in override:
            found = shutil.which(override)
            if found:
                return found
        elif Path(override).exists():
            return override
    candidates = ["/opt/rocm/bin/rocm-smi", shutil.which("rocm-smi")]
    for item in candidates:
        if item and Path(item).exists():
            return item
    return None


def _first(data: dict[str, Any], names: list[str]) -> Any:
    lowered = {key.lower(): value for key, value in data.items()}
    for name in names:
        if name in data:
            return data[name]
        if name.lower() in lowered:
            return lowered[name.lower()]
    return None


def _number(value: Any) -> int | float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return value
    text = str(value).strip().split()[0].replace("%", "")
    try:
        if "." in text:
            return float(text)
        return int(text)
    except ValueError:
        return None


def _parse_devices(payload: dict[str, Any]) -> list[dict[str, Any]]:
    devices: list[dict[str, Any]] = []
    for index, (key, value) in enumerate(payload.items()):
        if not isinstance(value, dict):
            continue
        devices.append(
            {
                "index": index,
                "id": key,
                "name": _first(value, ["Card series", "Card model", "GPU ID", "Name"]),
                "utilizationGpuPercent": _number(_first(value, ["GPU use (%)", "GPU use", "GPU Utilization (%)"])),
                "memoryUsedBytes": _number(_first(value, ["VRAM Total Used Memory (B)", "VRAM Used Memory (B)", "Memory Used (B)"])),
                "memoryTotalBytes": _number(_first(value, ["VRAM Total Memory (B)", "Memory Total (B)"])),
                "temperatureC": _number(_first(value, ["Temperature (Sensor edge) (C)", "Temperature (Sensor junction) (C)", "Temperature (C)"])),
            }
        )
    return devices


def read_rocm_metrics(timeout: float = 2.0) -> dict[str, Any]:
    binary = _find_rocm_smi()
    if not binary:
        return {"provider": "rocm-smi", "available": False, "reason": "binary_missing", "devices": []}
    try:
        proc = subprocess.run([binary, "--json"], check=False, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"provider": "rocm-smi", "available": False, "reason": "timeout", "devices": []}
    except OSError as exc:
        return {"provider": "rocm-smi", "available": False, "reason": "binary_error", "message": str(exc), "devices": []}
    if proc.returncode != 0:
        return {"provider": "rocm-smi", "available": False, "reason": "command_failed", "message": proc.stderr.strip(), "devices": []}
    try:
        payload = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError as exc:
        return {"provider": "rocm-smi", "available": False, "reason": "parse_error", "message": str(exc), "devices": []}
    if not isinstance(payload, dict):
        return {"provider": "rocm-smi", "available": False, "reason": "parse_error", "devices": []}
    return {"provider": "rocm-smi", "available": True, "devices": _parse_devices(payload)}
