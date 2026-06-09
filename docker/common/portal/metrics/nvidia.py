from __future__ import annotations

from typing import Any


def read_nvidia_metrics() -> dict[str, Any]:
    try:
        import pynvml  # type: ignore[import-not-found]
    except Exception:  # noqa: BLE001
        return {"provider": "nvidia-nvml", "available": False, "reason": "library_missing", "devices": []}

    try:
        pynvml.nvmlInit()
    except Exception as exc:  # noqa: BLE001
        return {"provider": "nvidia-nvml", "available": False, "reason": "driver_unavailable", "message": str(exc), "devices": []}

    devices: list[dict[str, Any]] = []
    try:
        count = pynvml.nvmlDeviceGetCount()
        for index in range(count):
            try:
                handle = pynvml.nvmlDeviceGetHandleByIndex(index)
                name = pynvml.nvmlDeviceGetName(handle)
                uuid = pynvml.nvmlDeviceGetUUID(handle)
                util = pynvml.nvmlDeviceGetUtilizationRates(handle)
                mem = pynvml.nvmlDeviceGetMemoryInfo(handle)
                try:
                    temp = pynvml.nvmlDeviceGetTemperature(handle, pynvml.NVML_TEMPERATURE_GPU)
                except Exception:  # noqa: BLE001
                    temp = None
                devices.append(
                    {
                        "index": index,
                        "name": name.decode("utf-8", errors="replace") if isinstance(name, bytes) else str(name),
                        "uuid": uuid.decode("utf-8", errors="replace") if isinstance(uuid, bytes) else str(uuid),
                        "utilizationGpuPercent": int(getattr(util, "gpu", 0)),
                        "utilizationMemoryPercent": int(getattr(util, "memory", 0)),
                        "memoryUsedBytes": int(getattr(mem, "used", 0)),
                        "memoryTotalBytes": int(getattr(mem, "total", 0)),
                        "temperatureC": temp,
                    }
                )
            except Exception as exc:  # noqa: BLE001
                devices.append({"index": index, "error": str(exc)})
        return {"provider": "nvidia-nvml", "available": True, "devices": devices}
    finally:
        try:
            pynvml.nvmlShutdown()
        except Exception:  # noqa: BLE001
            pass
