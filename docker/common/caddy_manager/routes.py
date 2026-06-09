from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml


@dataclass(frozen=True)
class Route:
    id: str
    match: str
    upstream: str
    auth: str = "required"
    preserve_host: bool = True
    description: str = ""

    @classmethod
    def from_mapping(cls, data: dict[str, Any]) -> "Route":
        route_id = str(data.get("id") or "").strip()
        match = str(data.get("match") or "").strip()
        upstream = str(data.get("upstream") or "").strip()
        if not route_id or not match or not upstream:
            raise ValueError("route entries require id, match, and upstream")
        auth = str(data.get("auth") or "required")
        if auth not in {"required", "excluded"}:
            raise ValueError(f"unsupported route auth mode for {route_id}: {auth}")
        return cls(
            id=route_id,
            match=match,
            upstream=upstream,
            auth=auth,
            preserve_host=bool(data.get("preserveHost", True)),
            description=str(data.get("description") or ""),
        )

    @property
    def upstream_port(self) -> int | None:
        parsed = urlsplit(self.upstream)
        return parsed.port

    @property
    def upstream_base(self) -> str:
        parsed = urlsplit(self.upstream)
        if parsed.scheme and parsed.netloc:
            return f"{parsed.scheme}://{parsed.netloc}"
        return self.upstream

    @property
    def upstream_path(self) -> str:
        parsed = urlsplit(self.upstream)
        return parsed.path or ""


def default_routes(portal_upstream: str = "http://127.0.0.1:8080") -> list[Route]:
    return [
        Route(id="health", match="/healthz", upstream=f"{portal_upstream}/api/v1/health", auth="excluded", preserve_host=True),
        Route(id="portal-api", match="/api/*", upstream=portal_upstream, auth="required", preserve_host=True),
        Route(id="example-service", match="/services/example/*", upstream="http://127.0.0.1:18080", auth="required", preserve_host=False),
        Route(id="portal", match="/", upstream=portal_upstream, auth="required", preserve_host=True),
    ]


def load_routes(path: Path, portal_upstream: str = "http://127.0.0.1:8080") -> list[Route]:
    if not path.exists():
        return default_routes(portal_upstream)
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    routes = [Route.from_mapping(item) for item in data.get("routes", [])]
    return routes or default_routes(portal_upstream)


def sort_routes(routes: list[Route]) -> list[Route]:
    def score(route: Route) -> tuple[int, int, str]:
        clean = route.match.replace("*", "")
        return (len(clean), clean.count("/"), route.id)

    return sorted(routes, key=score, reverse=True)


def is_local_upstream(upstream: str) -> bool:
    parsed = urlsplit(upstream)
    host = parsed.hostname or ""
    return host in {"127.0.0.1", "localhost", "::1"}
