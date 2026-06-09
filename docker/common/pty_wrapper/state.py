from __future__ import annotations

import json
import os
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


@dataclass
class WrapperContext:
    run_id: str
    log_dir: Path = Path("/tmp/xforce-ai/pty")
    state_dir: Path | None = None
    cwd: Path | None = None
    term: str = "xterm-256color"
    cols: int = 120
    rows: int = 40
    forward_console: bool = True
    strip_ansi: bool = True
    terminate_timeout: float = 10.0
    kill_timeout: float = 5.0
    json_output: bool = False
    env_overrides: dict[str, str] = field(default_factory=dict)

    def resolve(self) -> "WrapperContext":
        self.log_dir = self.log_dir.resolve()
        if self.state_dir is None:
            self.state_dir = self.log_dir
        else:
            self.state_dir = self.state_dir.resolve()
        if self.cwd is not None:
            self.cwd = self.cwd.resolve()
        return self

    @property
    def run_dir(self) -> Path:
        return self.log_dir / self.run_id

    @property
    def ansi_log(self) -> Path:
        return self.run_dir / "stdout.ansi.log"

    @property
    def plain_log(self) -> Path:
        return self.run_dir / "stdout.plain.log"

    @property
    def state_env(self) -> Path:
        return self.run_dir / "state.env"

    @property
    def state_json(self) -> Path:
        return self.run_dir / "state.json"


@dataclass
class WrapperState:
    run_id: str
    command: list[str]
    pid: int | None = None
    pgid: int | None = None
    status: str = "starting"
    exit_code: int | None = None
    signal: int | None = None
    started_at: str = ""
    ended_at: str = ""
    ansi_log: str = ""
    plain_log: str = ""
    cwd: str = ""

    def to_env_lines(self) -> list[str]:
        return [
            f"XFORCE_PTY_STATUS={self.status}",
            f"XFORCE_PTY_RUN_ID={self.run_id}",
            f"XFORCE_PTY_PID={self.pid or ''}",
            f"XFORCE_PTY_PGID={self.pgid or ''}",
            f"XFORCE_PTY_COMMAND={' '.join(self.command)}",
            f"XFORCE_PTY_EXIT_CODE={self.exit_code if self.exit_code is not None else ''}",
            f"XFORCE_PTY_SIGNAL={self.signal or ''}",
            f"XFORCE_PTY_STARTED_AT={self.started_at}",
            f"XFORCE_PTY_ENDED_AT={self.ended_at}",
            f"XFORCE_PTY_ANSI_LOG={self.ansi_log}",
            f"XFORCE_PTY_PLAIN_LOG={self.plain_log}",
        ]

    def to_json(self) -> dict[str, Any]:
        data = asdict(self)
        data["apiVersion"] = "xforce.ai/pty-state/v1"
        return data


def write_state_files(ctx: WrapperContext, state: WrapperState) -> None:
    ctx.run_dir.mkdir(parents=True, exist_ok=True)
    ctx.state_env.write_text("\n".join(state.to_env_lines()) + "\n", encoding="utf-8")
    ctx.state_json.write_text(json.dumps(state.to_json(), indent=2, sort_keys=True) + "\n", encoding="utf-8")

