from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _path_env(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default))


@dataclass(frozen=True)
class CaddyManagerConfig:
    http_addr: str = ":8088"
    admin_addr: str = "127.0.0.1:2019"
    routes_path: Path = Path("/etc/xforce-ai/caddy/routes.yaml")
    auth_path: Path = Path("/etc/xforce-ai/caddy/auth.yaml")
    output_path: Path = Path("/tmp/xforce-ai/caddy/Caddyfile.generated")
    caddy_bin: str = "caddy"
    portal_upstream: str = "http://127.0.0.1:8080"
    auth_exclude: str = ""

    @classmethod
    def from_env(cls) -> "CaddyManagerConfig":
        return cls(
            http_addr=os.environ.get("XFORCE_CADDY_HTTP_ADDR", ":8088"),
            admin_addr=os.environ.get("XFORCE_CADDY_ADMIN_ADDR", "127.0.0.1:2019"),
            routes_path=_path_env("XFORCE_CADDY_ROUTES", "/etc/xforce-ai/caddy/routes.yaml"),
            auth_path=_path_env("XFORCE_CADDY_AUTH", "/etc/xforce-ai/caddy/auth.yaml"),
            output_path=_path_env("XFORCE_CADDY_GENERATED_CONFIG", "/tmp/xforce-ai/caddy/Caddyfile.generated"),
            caddy_bin=os.environ.get("XFORCE_CADDY_BIN", "caddy"),
            portal_upstream=os.environ.get("XFORCE_PORTAL_UPSTREAM", "http://127.0.0.1:8080"),
            auth_exclude=os.environ.get("AUTH_EXCLUDE", ""),
        )
