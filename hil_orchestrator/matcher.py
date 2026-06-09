from __future__ import annotations

import uuid
from typing import Any

from .inventory import InventoryCandidate, eligible_state
from .models import ModelRequirement


def _feature_ok(candidate: InventoryCandidate, feature: str) -> bool:
    return bool(candidate.features.get(feature))


def candidate_reasons(model: ModelRequirement, candidate: InventoryCandidate, allow_degraded: bool = False, max_price_per_hour: float | None = None) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    ok = True
    if not eligible_state(candidate, allow_degraded):
        ok = False
        reasons.append("no_certified_active_gpu")
    else:
        reasons.append("certified_active" if candidate.state == "Certified_Active" else "certified_degraded")
    if bool(candidate.node.get("is_leased")):
        ok = False
        reasons.append("gpu_already_leased")
    if candidate.certification_expired():
        ok = False
        reasons.append("certification_expired")
    if candidate.vram_gb < model.min_vram_gb:
        ok = False
        reasons.append("min_vram_not_satisfied")
    if model.min_compute_capability is not None and (candidate.compute_capability is None or candidate.compute_capability < model.min_compute_capability):
        ok = False
        reasons.append("compute_capability_not_satisfied")
    if model.allowed_gpu_vendors and candidate.vendor not in model.allowed_gpu_vendors:
        ok = False
        reasons.append("gpu_vendor_not_allowed")
    if candidate.gpu_model in model.excluded_gpu_models:
        ok = False
        reasons.append("gpu_model_excluded")
    missing_features = [feature for feature in model.required_features if not _feature_ok(candidate, feature)]
    if missing_features:
        ok = False
        reasons.append("required_features_missing")
    if max_price_per_hour is not None and candidate.price_per_hour > max_price_per_hour:
        ok = False
        reasons.append("price_limit_too_low")
    if candidate.gpu_model in model.preferred_gpu_models:
        reasons.append("preferred_gpu_model")
    if max_price_per_hour is not None and candidate.price_per_hour <= max_price_per_hour:
        reasons.append("price_within_limit")
    return ok, reasons


def _score(model: ModelRequirement, candidate: InventoryCandidate) -> float:
    score = 0.5
    if candidate.gpu_model in model.preferred_gpu_models:
        score += 0.2
    if candidate.vram_gb >= model.recommended_vram_gb:
        score += 0.1
    score += min(candidate.reputation_score / 1000, 0.1)
    score += max(0.0, 0.1 - candidate.price_per_hour / 100)
    return round(min(score, 0.99), 4)


def preflight(model: ModelRequirement, inventory: list[InventoryCandidate], quantity: int = 1, max_price_per_hour: float | None = None, allow_degraded: bool = False, request_id: str | None = None) -> dict[str, Any]:
    matches: list[tuple[InventoryCandidate, list[str]]] = []
    rejected_reasons: set[str] = set()
    for candidate in inventory:
        ok, reasons = candidate_reasons(model, candidate, allow_degraded, max_price_per_hour)
        if ok:
            matches.append((candidate, reasons))
        else:
            rejected_reasons.update(reasons)

    def sort_key(item: tuple[InventoryCandidate, list[str]]) -> tuple[int, float, float, str, str]:
        candidate, _reasons = item
        preferred = 0 if candidate.gpu_model in model.preferred_gpu_models else 1
        return (preferred, candidate.price_per_hour, -candidate.reputation_score, candidate.node_id, candidate.device_fingerprint)

    ranked = sorted(matches, key=sort_key)[: max(quantity, model.max_candidates)]
    candidates = [
        {
            "node_id": candidate.node_id,
            "device_fingerprint": candidate.device_fingerprint,
            "gpu_model": candidate.gpu_model,
            "vram_gb": candidate.vram_gb,
            "price_per_hour": candidate.price_per_hour,
            "certification_report_id": candidate.certification.get("report_id"),
            "match_score": _score(model, candidate),
            "reasons": reasons,
        }
        for candidate, reasons in ranked
    ]
    status = "available" if len(candidates) >= quantity else "unavailable"
    return {
        "request_id": request_id or f"preflight-{uuid.uuid4().hex[:12]}",
        "model_id": model.model_id,
        "status": status,
        "candidates": candidates,
        "reasons": [] if candidates else sorted(rejected_reasons or {"no_matching_gpu"}),
        "fallbacks": [] if candidates else [model.fallback_policy],
    }
