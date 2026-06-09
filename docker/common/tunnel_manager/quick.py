from __future__ import annotations

import subprocess
from typing import Any

from .config import TunnelConfig
from .parser import parse_quick_url
from .state import write_state


def quick_command(cfg: TunnelConfig) -> list[str]:
    return [cfg.cloudflared_bin, "tunnel", "--url", cfg.url, "--metrics", cfg.metrics, "--no-autoupdate"]


def run_quick(cfg: TunnelConfig, dry_run: bool = False) -> dict[str, Any]:
    command = quick_command(cfg)
    if dry_run:
        payload = {"mode": "quick", "status": "dry_run", "command": command, "url": cfg.url, "metrics": cfg.metrics}
        write_state(cfg.state_dir, payload)
        return payload
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = ""
    quick_url = None
    assert proc.stdout is not None
    for line in proc.stdout:
        print(line, end="")
        output += line
        quick_url = quick_url or parse_quick_url(line)
        if quick_url:
            cfg.state_dir.mkdir(parents=True, exist_ok=True)
            (cfg.state_dir / "quick-url.txt").write_text(quick_url + "\n", encoding="utf-8")
            write_state(cfg.state_dir, {"mode": "quick", "status": "running", "quickUrl": quick_url, "command": command})
    returncode = proc.wait()
    payload = {"mode": "quick", "status": "exited", "returncode": returncode, "quickUrl": quick_url, "command": command}
    write_state(cfg.state_dir, payload)
    return payload
