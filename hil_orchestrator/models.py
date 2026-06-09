from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ModelRequirement:
    model_id: str
    display_name: str
    image_reference: str
    variant_preference: tuple[str, ...]
    min_vram_gb: float
    recommended_vram_gb: float
    min_system_ram_gb: float
    min_disk_gb: float
    min_compute_capability: float | None
    allowed_gpu_vendors: tuple[str, ...]
    preferred_gpu_models: tuple[str, ...]
    excluded_gpu_models: tuple[str, ...]
    required_features: tuple[str, ...]
    fallback_policy: str
    max_candidates: int
    require_fresh_certification_days: int

    @classmethod
    def from_mapping(cls, data: dict[str, Any]) -> "ModelRequirement":
        image = data.get("image") or {}
        hardware = data.get("hardware") or {}
        scheduling = data.get("scheduling") or {}
        required = ["model_id"]
        missing = [key for key in required if not data.get(key)]
        for key in ("min_vram_gb", "min_system_ram_gb", "min_disk_gb", "multi_gpu_allowed"):
            if key not in hardware:
                missing.append(f"hardware.{key}")
        if not image.get("reference"):
            missing.append("image.reference")
        if not scheduling.get("strategy"):
            missing.append("scheduling.strategy")
        if missing:
            raise ValueError(f"model {data.get('model_id', '<unknown>')} missing required fields: {', '.join(missing)}")
        return cls(
            model_id=str(data["model_id"]),
            display_name=str(data.get("display_name") or data["model_id"]),
            image_reference=str(image["reference"]),
            variant_preference=tuple(str(item) for item in image.get("variant_preference", [])),
            min_vram_gb=float(hardware["min_vram_gb"]),
            recommended_vram_gb=float(hardware.get("recommended_vram_gb") or hardware["min_vram_gb"]),
            min_system_ram_gb=float(hardware["min_system_ram_gb"]),
            min_disk_gb=float(hardware["min_disk_gb"]),
            min_compute_capability=float(hardware["min_compute_capability"]) if hardware.get("min_compute_capability") is not None else None,
            allowed_gpu_vendors=tuple(str(item).lower() for item in hardware.get("allowed_gpu_vendors", [])),
            preferred_gpu_models=tuple(str(item) for item in hardware.get("preferred_gpu_models", [])),
            excluded_gpu_models=tuple(str(item) for item in hardware.get("excluded_gpu_models", [])),
            required_features=tuple(str(item) for item in hardware.get("required_features", [])),
            fallback_policy=str(scheduling.get("fallback_policy") or "strict"),
            max_candidates=int(scheduling.get("max_candidates") or 5),
            require_fresh_certification_days=int(scheduling.get("require_fresh_certification_days") or 30),
        )


def load_model_registry(data: dict[str, Any]) -> dict[str, ModelRequirement]:
    models = [ModelRequirement.from_mapping(item) for item in data.get("models", [])]
    return {item.model_id: item for item in models}
