from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


SECRET_KEYS = ("TOKEN", "PASSWORD", "SECRET", "KEY", "AUTH", "BEARER")


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def mask_value(key: str, value: Any) -> Any:
    upper = key.upper()
    if any(part in upper for part in SECRET_KEYS):
        return "***MASKED***"
    return value


def canonical_json(data: Any) -> str:
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_key(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-._")
    return safe or sha256_text(value)[:16]


@dataclass
class ProvisionContext:
    state_dir: Path
    cache_dir: Path
    manifest_cache_dir: Path
    boot_state_dir: Path
    workspace_dir: Path
    venv_dir: Path
    max_retries: int = 3
    backoff_base_seconds: float = 1.0
    backoff_max_seconds: float = 30.0
    dry_run: bool = False
    force: bool = False
    no_retry: bool = False
    env: dict[str, str] = field(default_factory=lambda: dict(os.environ))

    @classmethod
    def from_env(cls, args: Any | None = None) -> "ProvisionContext":
        env = dict(os.environ)
        state_dir = Path(getattr(args, "state_dir", None) or env.get("XFORCE_PROVISION_STATE_DIR", "/.provisioner_state"))
        cache_dir = Path(getattr(args, "cache_dir", None) or env.get("XFORCE_PROVISION_CACHE_DIR", str(state_dir / "downloads")))
        return cls(
            state_dir=state_dir,
            cache_dir=cache_dir,
            manifest_cache_dir=Path(env.get("XFORCE_PROVISION_MANIFEST_CACHE_DIR", str(state_dir / "manifests"))),
            boot_state_dir=Path(env.get("XFORCE_PROVISION_BOOT_STATE_DIR", env.get("XFORCE_BOOT_STATE_DIR", "/tmp/xforce-ai"))),
            workspace_dir=Path(getattr(args, "workspace_dir", None) or env.get("WORKSPACE_DIR", "/workspace")),
            venv_dir=Path(getattr(args, "venv_dir", None) or env.get("VENV_DIR", "/venv/main")),
            max_retries=int(env.get("XFORCE_PROVISION_MAX_RETRIES", "3")),
            backoff_base_seconds=float(env.get("XFORCE_PROVISION_BACKOFF_BASE_SECONDS", "1")),
            backoff_max_seconds=float(env.get("XFORCE_PROVISION_BACKOFF_MAX_SECONDS", "30")),
            dry_run=bool(getattr(args, "dry_run", False)),
            force=bool(getattr(args, "force", False)),
            no_retry=bool(getattr(args, "no_retry", False)),
            env=env,
        )

    def ensure_dirs(self) -> None:
        for path in [self.state_dir, self.cache_dir, self.manifest_cache_dir, self.boot_state_dir, self.state_dir / "stages", self.state_dir / "locks"]:
            path.mkdir(parents=True, exist_ok=True)


def stage_key(manifest_name: str, stage_id: str) -> str:
    return safe_key(f"{manifest_name}/{stage_id}")


def stage_state_path(ctx: ProvisionContext, manifest_name: str, stage_id: str) -> Path:
    return ctx.state_dir / "stages" / f"{stage_key(manifest_name, stage_id)}.json"


def read_stage_state(ctx: ProvisionContext, manifest_name: str, stage_id: str) -> dict[str, Any] | None:
    path = stage_state_path(ctx, manifest_name, stage_id)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def write_stage_state(ctx: ProvisionContext, manifest_name: str, stage: dict[str, Any], status: str, stage_hash: str, *, attempts: int = 0, error: str = "", outputs: list[str] | None = None) -> None:
    path = stage_state_path(ctx, manifest_name, str(stage["id"]))
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "apiVersion": "xforce.ai/state/v1",
        "stageId": stage["id"],
        "stageType": stage["type"],
        "stageHash": stage_hash,
        "status": status,
        "updatedAt": utc_now(),
        "attempts": attempts,
        "error": error,
        "outputs": outputs or [],
    }
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def write_summary(ctx: ProvisionContext, *, status: str, manifest: str = "", manifest_source: str = "none", total: int = 0, completed: int = 0, skipped: int = 0, failed: int = 0, last_error: str = "") -> None:
    ctx.boot_state_dir.mkdir(parents=True, exist_ok=True)
    summary = ctx.boot_state_dir / "provisioner.env"
    lines = {
        "XFORCE_PROVISION_STATUS": status,
        "XFORCE_PROVISION_MANIFEST": manifest,
        "XFORCE_PROVISION_MANIFEST_SOURCE": manifest_source,
        "XFORCE_PROVISION_STATE_DIR": str(ctx.state_dir),
        "XFORCE_PROVISION_STAGE_TOTAL": str(total),
        "XFORCE_PROVISION_STAGE_COMPLETED": str(completed),
        "XFORCE_PROVISION_STAGE_SKIPPED": str(skipped),
        "XFORCE_PROVISION_STAGE_FAILED": str(failed),
        "XFORCE_PROVISION_LAST_ERROR": last_error,
    }
    summary.write_text("".join(f"{k}={mask_value(k, v)}\n" for k, v in lines.items()), encoding="utf-8")


def stage_hash(ctx: ProvisionContext, stage: dict[str, Any]) -> str:
    data: dict[str, Any] = {"stage": stage}
    if stage.get("type") == "pip":
        requirements_hashes: list[dict[str, str]] = []
        for item in stage.get("requirements", []) or []:
            path = Path(item)
            if path.exists():
                requirements_hashes.append({"path": str(path), "sha256": sha256_file(path)})
        data["requirements"] = requirements_hashes
        python_bin = Path(stage.get("venv") or ctx.venv_dir) / "bin" / "python"
        if python_bin.exists():
            try:
                data["pythonVersion"] = subprocess.check_output([str(python_bin), "--version"], text=True, stderr=subprocess.STDOUT).strip()
            except Exception:
                data["pythonVersion"] = "unknown"
    return sha256_text(canonical_json(data))
