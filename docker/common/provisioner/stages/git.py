from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from ..retry import RetryableError, run_with_retry
from ..state import ProvisionContext


def _run(cmd: list[str], *, cwd: Path | None = None) -> None:
    try:
        subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True)
    except subprocess.CalledProcessError as exc:
        raise RetryableError(f"command failed: {' '.join(cmd)}") from exc


def run_git_stage(ctx: ProvisionContext, stage: dict[str, Any]) -> list[str]:
    repo = str(stage["repo"])
    dest = Path(stage["dest"])
    ref = str(stage.get("ref", "main"))
    depth = stage.get("depth")
    if ctx.dry_run:
        return [f"git:{repo}->{dest}@{ref}"]
    if dest.exists() and not (dest / ".git").exists():
        if not stage.get("allowExisting"):
            raise FileExistsError(f"destination exists and is not a git repository: {dest}")
        return [f"git:existing:{dest}"]

    def op() -> None:
        if not dest.exists():
            cmd = ["git", "clone"]
            if depth:
                cmd.extend(["--depth", str(depth)])
            cmd.extend([repo, str(dest)])
            _run(cmd)
        else:
            _run(["git", "fetch", "--all", "--tags"], cwd=dest)
        _run(["git", "checkout", ref], cwd=dest)
        if stage.get("submodules"):
            _run(["git", "submodule", "update", "--init", "--recursive"], cwd=dest)

    run_with_retry(op, retries=0 if ctx.no_retry else int(stage.get("retries", ctx.max_retries)), base_seconds=ctx.backoff_base_seconds, max_seconds=ctx.backoff_max_seconds)
    return [f"git:{dest}"]
