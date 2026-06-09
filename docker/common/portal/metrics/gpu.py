from __future__ import annotations

from typing import Any

from .nvidia import read_nvidia_metrics
from .rocm import read_rocm_metrics


def read_gpu_metrics() -> dict[str, Any]:
    providers = [read_nvidia_metrics(), read_rocm_metrics()]
    return {"providers": providers, "available": any(item.get("available") for item in providers)}
