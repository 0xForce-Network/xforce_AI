from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any

from .artifacts import publish_local
from .config import load_data, utc_now, write_json
from .providers.fixture import FixtureProvider
from .states import CERTIFICATION_FAILED, CERTIFIED_ACTIVE, CERTIFIED_DEGRADED


def _suite_by_id(suites_data: dict[str, Any], suite_id: str) -> dict[str, Any]:
    for suite in suites_data.get("suites", []):
        if suite.get("suite_id") == suite_id:
            return suite
    raise KeyError(suite_id)


def run_fixture_validation(suite_path: Path, inventory_path: Path, suite_id: str, node_id: str | None, state_dir: Path, artifact_dir: Path, fail_on_degraded: bool = False) -> dict[str, Any]:
    suites_data = load_data(suite_path)
    suite = _suite_by_id(suites_data, suite_id)
    provider = FixtureProvider(inventory_path, state_dir / "leases")
    candidates = provider.list_candidates(suite.get("required_features", {}))
    if node_id:
        candidates = [candidate for candidate in candidates if candidate["node_id"] == node_id]
    if not candidates:
        raise RuntimeError("no fixture candidate available")
    lease = provider.acquire(candidates[0], {"suite_id": suite_id, "node_id": node_id or candidates[0]["node_id"]})
    started_at = utc_now()
    steps = []
    required_failed = False
    optional_failed = False
    for step in suite.get("steps", []):
        status = str(step.get("fixture_status") or "passed")
        required = bool(step.get("required", True))
        steps.append({"id": step.get("id"), "runner": step.get("runner"), "required": required, "status": status})
        if status != "passed" and required:
            required_failed = True
        if status != "passed" and not required:
            optional_failed = True
    if required_failed:
        status = "failed"
        certification_state = CERTIFICATION_FAILED
    elif optional_failed and not fail_on_degraded:
        status = "degraded"
        certification_state = CERTIFIED_DEGRADED
    else:
        status = "passed"
        certification_state = CERTIFIED_ACTIVE
    candidate = candidates[0]
    report = {
        "apiVersion": "xforce.ai/hil-report/v1",
        "report_id": f"hil-report-{uuid.uuid4().hex[:12]}",
        "trigger_type": "fixture",
        "status": status,
        "certification_state": certification_state,
        "node_id": candidate["node_id"],
        "lease_id": lease["lease_id"],
        "verification_epoch_id": f"fixture-{started_at[:10]}",
        "gpu": {
            "device_fingerprint": candidate["device_fingerprint"],
            "gpu_model": candidate["gpu_model"],
            "vram_gb": candidate["vram_gb"],
            "compute_capability": candidate["compute_capability"],
        },
        "suite": {"suite_id": suite_id, "started_at": started_at, "completed_at": utc_now()},
        "steps": steps,
        "artifacts": [],
        "policy": {"degraded_allowed": not fail_on_degraded},
    }
    if status in {"passed", "degraded"}:
        report["artifacts"].append(publish_local(report, artifact_dir))
    report_path = state_dir / "reports" / f"{report['report_id']}.json"
    write_json(report_path, report)
    provider.release(lease["lease_id"])
    report["report_path"] = str(report_path)
    write_json(report_path, report)
    return report
