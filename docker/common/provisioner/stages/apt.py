from __future__ import annotations

import os
import subprocess
from typing import Any

from ..retry import RetryableError, run_with_retry
from ..state import ProvisionContext


def _run(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as exc:
        raise RetryableError(f"command failed: {' '.join(cmd)}") from exc


def run_apt_stage(ctx: ProvisionContext, stage: dict[str, Any]) -> list[str]:
    if os.geteuid() != 0 and not ctx.env.get("XFORCE_APT_GET_BIN"):
        raise PermissionError("apt stages require root privileges")
    apt_get = ctx.env.get("XFORCE_APT_GET_BIN", "apt-get")
    packages = [str(item) for item in stage.get("packages", [])]
    install_cmd = [apt_get, "install", "-y"]
    if not bool(stage.get("installRecommends", False)):
        install_cmd.append("--no-install-recommends")
    install_cmd.extend(packages)
    commands: list[list[str]] = []
    if bool(stage.get("update", True)):
        commands.append([apt_get, "update"])
    commands.append(install_cmd)
    if ctx.dry_run:
        return [" ".join(cmd) for cmd in commands]
    for cmd in commands:
        run_with_retry(lambda cmd=cmd: _run(cmd), retries=0 if ctx.no_retry else int(stage.get("retries", ctx.max_retries)), base_seconds=ctx.backoff_base_seconds, max_seconds=ctx.backoff_max_seconds)
    return ["apt:" + ",".join(packages)]
