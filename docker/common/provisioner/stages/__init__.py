from __future__ import annotations

from typing import Any

from ..state import ProvisionContext
from .apt import run_apt_stage
from .download import run_download_stage, run_model_stage
from .git import run_git_stage
from .pip import run_pip_stage


def run_stage(ctx: ProvisionContext, stage: dict[str, Any]) -> list[str]:
    stage_type = stage["type"]
    if stage_type == "apt":
        return run_apt_stage(ctx, stage)
    if stage_type == "pip":
        return run_pip_stage(ctx, stage)
    if stage_type == "git":
        return run_git_stage(ctx, stage)
    if stage_type == "download":
        return run_download_stage(ctx, stage)
    if stage_type == "model":
        return run_model_stage(ctx, stage)
    raise ValueError(f"unsupported stage type: {stage_type}")
