from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from .config import PortalConfig


@dataclass(frozen=True)
class ServiceSpec:
    name: str
    supervisor_name: str
    title: str
    category: str
    protected: bool
    autostart: bool
    log_mode: str
    description: str = ""
    pty_run_id: str | None = None

    @classmethod
    def from_mapping(cls, data: dict[str, Any]) -> "ServiceSpec":
        name = str(data.get("name", "")).strip()
        supervisor_name = str(data.get("supervisorName", name)).strip()
        if not name or not supervisor_name:
            raise ValueError("service entries require name and supervisorName")
        log_mode = str(data.get("logMode", "supervisor"))
        if log_mode not in {"supervisor", "pty"}:
            raise ValueError(f"unsupported logMode for {name}: {log_mode}")
        return cls(
            name=name,
            supervisor_name=supervisor_name,
            title=str(data.get("title", name)),
            category=str(data.get("category", "user")),
            protected=bool(data.get("protected", False)),
            autostart=bool(data.get("autostart", False)),
            log_mode=log_mode,
            description=str(data.get("description", "")),
            pty_run_id=str(data["ptyRunId"]) if data.get("ptyRunId") else None,
        )

    def base_response(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "supervisorName": self.supervisor_name,
            "title": self.title,
            "category": self.category,
            "protected": self.protected,
            "autostart": self.autostart,
            "logMode": self.log_mode,
            "ptyRunId": self.pty_run_id,
            "description": self.description,
        }


def _default_specs() -> list[ServiceSpec]:
    return [
        ServiceSpec(
            name="portal-backend",
            supervisor_name="portal-backend",
            title="Instance Portal Backend",
            category="core",
            protected=True,
            autostart=True,
            log_mode="supervisor",
            description="Local FastAPI control backend.",
        ),
        ServiceSpec(
            name="example-pty-service",
            supervisor_name="example-pty-service",
            title="Example PTY Service",
            category="fixture",
            protected=False,
            autostart=False,
            log_mode="pty",
            pty_run_id="example-pty-service",
            description="Disabled fixture service for lifecycle smoke tests.",
        ),
    ]


class ServiceRegistry:
    def __init__(self, specs: list[ServiceSpec]) -> None:
        self._by_name = {item.name: item for item in specs}
        self._by_supervisor = {item.supervisor_name: item for item in specs}

    @classmethod
    def load(cls, path: Path) -> "ServiceRegistry":
        if not path.exists():
            return cls(_default_specs())
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        specs = [ServiceSpec.from_mapping(item) for item in data.get("services", [])]
        return cls(specs or _default_specs())

    def all(self) -> list[ServiceSpec]:
        return list(self._by_name.values())

    def get(self, name: str) -> ServiceSpec | None:
        return self._by_name.get(name)


def service_log_paths(cfg: PortalConfig, spec: ServiceSpec) -> dict[str, Path]:
    base = cfg.service_log_dir / spec.name
    paths = {
        "stdout": base / "stdout.log",
        "stderr": base / "stderr.log",
    }
    if spec.log_mode == "pty" and spec.pty_run_id:
        pty_base = cfg.pty_log_dir / spec.pty_run_id
        paths["ansi"] = pty_base / "stdout.ansi.log"
        paths["plain"] = pty_base / "stdout.plain.log"
    return paths


def merge_status(spec: ServiceSpec, process_info: dict[str, Any] | None) -> dict[str, Any]:
    result = spec.base_response()
    if not process_info:
        result.update(
            {
                "state": "UNKNOWN",
                "pid": 0,
                "uptimeSeconds": 0,
                "spawnerr": "supervisor_unavailable",
            }
        )
        return result
    state = str(process_info.get("statename") or process_info.get("state") or "UNKNOWN")
    pid = int(process_info.get("pid") or 0)
    start = int(process_info.get("start") or 0)
    uptime = max(0, int(time.time()) - start) if pid > 0 and start > 0 and state == "RUNNING" else 0
    result.update(
        {
            "state": state,
            "pid": pid,
            "uptimeSeconds": uptime,
            "spawnerr": str(process_info.get("spawnerr") or ""),
        }
    )
    return result
