from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TunnelConfig:
    url: str = "http://127.0.0.1:8088"
    metrics: str = "127.0.0.1:20241"
    token_env: str = "CF_TUNNEL_TOKEN"
    cloudflared_bin: str = "cloudflared"
    state_dir: Path = Path("/tmp/xforce-ai/tunnel")
    mode: str = "auto"

    @classmethod
    def from_env(cls) -> "TunnelConfig":
        return cls(
            url=os.environ.get("XFORCE_TUNNEL_URL", "http://127.0.0.1:8088"),
            metrics=os.environ.get("XFORCE_TUNNEL_METRICS", "127.0.0.1:20241"),
            token_env=os.environ.get("XFORCE_TUNNEL_TOKEN_ENV", "CF_TUNNEL_TOKEN"),
            cloudflared_bin=os.environ.get("XFORCE_CLOUDFLARED_BIN", "cloudflared"),
            state_dir=Path(os.environ.get("XFORCE_TUNNEL_STATE_DIR", "/tmp/xforce-ai/tunnel")),
            mode=os.environ.get("XFORCE_TUNNEL_ON_BOOT", "auto"),
        )
