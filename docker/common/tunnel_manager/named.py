from __future__ import annotations

import os
import subprocess
from typing import Any

from .config import TunnelConfig
from .state import masked_command, write_state


def named_command(cfg: TunnelConfig, token: str) -> list[str]:
    return [cfg.cloudflared_bin, "tunnel", "run", "--token", token, "--metrics", cfg.metrics]


def run_named(cfg: TunnelConfig, dry_run: bool = False) -> dict[str, Any]:
    token = os.environ.get(cfg.token_env, "")
    if not token:
        payload = {"mode": "named", "status": "skipped", "reason": "token_missing", "tokenEnv": cfg.token_env}
        write_state(cfg.state_dir, payload)
        return payload
    command = named_command(cfg, token)
    payload = {"mode": "named", "status": "dry_run" if dry_run else "running", "command": masked_command(command, token), "tokenEnv": cfg.token_env, "metrics": cfg.metrics}
    write_state(cfg.state_dir, payload)
    if dry_run:
        return payload
    proc = subprocess.run(command, check=False)
    payload.update({"status": "exited", "returncode": proc.returncode})
    write_state(cfg.state_dir, payload)
    return payload
