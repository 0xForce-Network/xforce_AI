from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from ..retry import RetryableError, run_with_retry
from ..state import ProvisionContext


def _run(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        raise RetryableError(f"command failed: {' '.join(cmd)}") from exc


def run_pip_stage(ctx: ProvisionContext, stage: dict[str, Any]) -> list[str]:
    venv = Path(stage.get("venv") or ctx.venv_dir)
    python = venv / "bin" / "python"
    if not python.exists():
        raise FileNotFoundError(f"missing venv python: {python}")
    cmd = [str(python), "-m", "pip", "install"]
    cmd.extend(str(item) for item in stage.get("extraArgs", []) or [])
    for req in stage.get("requirements", []) or []:
        cmd.extend(["-r", str(req)])
    cmd.extend(str(pkg) for pkg in stage.get("packages", []) or [])
    if ctx.dry_run:
        return [" ".join(cmd)]
    run_with_retry(lambda: _run(cmd), retries=0 if ctx.no_retry else int(stage.get("retries", ctx.max_retries)), base_seconds=ctx.backoff_base_seconds, max_seconds=ctx.backoff_max_seconds)
    return ["pip"]
