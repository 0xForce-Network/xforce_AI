from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .routes import Route, is_local_upstream, sort_routes


@dataclass(frozen=True)
class AuthExclude:
    paths: tuple[str, ...] = ()
    route_ids: tuple[str, ...] = ()
    ports: tuple[int, ...] = ()


def parse_auth_exclude(value: str) -> AuthExclude:
    paths: list[str] = []
    route_ids: list[str] = []
    ports: list[int] = []
    for raw in value.split(","):
        item = raw.strip()
        if not item:
            continue
        if item.startswith("route:"):
            route_ids.append(item.split(":", 1)[1])
        elif item.startswith("port:"):
            try:
                ports.append(int(item.split(":", 1)[1]))
            except ValueError:
                continue
        else:
            paths.append(item)
    return AuthExclude(tuple(paths), tuple(route_ids), tuple(ports))


def _matcher_path(match: str) -> str:
    if match == "/":
        return "/*"
    return match


def _path_excludes_route(route: Route, excludes: AuthExclude) -> bool:
    normalized = route.match.rstrip("*")
    for path in excludes.paths:
        if route.match == path or normalized.startswith(path.rstrip("*")) or path.startswith(normalized.rstrip("/")):
            return True
    return False


def route_auth_excluded(route: Route, excludes: AuthExclude) -> bool:
    return route.auth == "excluded" or route.id in excludes.route_ids or (route.upstream_port in excludes.ports if route.upstream_port else False) or _path_excludes_route(route, excludes)


def render_caddyfile(routes: list[Route], http_addr: str, admin_addr: str, auth_exclude: str = "") -> str:
    excludes = parse_auth_exclude(auth_exclude)
    lines: list[str] = [
        "{",
        f"\tadmin {admin_addr}",
        "}",
        "",
        f"{http_addr} {{",
        "\tencode zstd gzip",
        "\tlog {",
        "\t\toutput file /tmp/xforce-ai/caddy/caddy.log",
        "\t}",
        "\theader {",
        "\t\tX-Content-Type-Options nosniff",
        "\t\tX-Frame-Options SAMEORIGIN",
        "\t\tReferrer-Policy no-referrer",
        "\t}",
        f"\t# AUTH_EXCLUDE={auth_exclude or '<empty>'}",
        "",
    ]
    for route in sort_routes(routes):
        if not is_local_upstream(route.upstream):
            raise ValueError(f"route {route.id} upstream must be local-only: {route.upstream}")
        matcher = f"route_{route.id.replace('-', '_')}"
        lines.extend([f"\t@{matcher} path {_matcher_path(route.match)}", f"\thandle @{matcher} {{", f"\t\t# route_id={route.id}"])
        if route_auth_excluded(route, excludes):
            lines.append("\t\t# auth=excluded")
        else:
            lines.extend([
                "\t\t# auth=required",
                "\t\tforward_auth 127.0.0.1:8080 {",
                "\t\t\turi /api/v1/auth/check",
                "\t\t\tcopy_headers Set-Cookie",
                "\t\t}",
            ])
        if route.strip_prefix:
            lines.append(f"\t\turi strip_prefix {route.strip_prefix}")
        if route.upstream_path:
            lines.append(f"\t\trewrite * {route.upstream_path}")
        lines.append(f"\t\treverse_proxy {route.upstream_base} {{")
        if route.flush_interval:
            lines.append(f"\t\t\tflush_interval {route.flush_interval}")
        if route.read_timeout or route.write_timeout or route.dial_timeout or route.keepalive:
            lines.append("\t\t\ttransport http {")
            if route.read_timeout:
                lines.append(f"\t\t\t\tread_timeout {route.read_timeout}")
            if route.write_timeout:
                lines.append(f"\t\t\t\twrite_timeout {route.write_timeout}")
            if route.dial_timeout:
                lines.append(f"\t\t\t\tdial_timeout {route.dial_timeout}")
            if route.keepalive:
                lines.append(f"\t\t\t\tkeepalive {route.keepalive}")
            lines.append("\t\t\t}")
        lines.append("\t\t\theader_up X-Forwarded-Proto {scheme}")
        lines.append("\t\t\theader_up X-Request-Id {http.request.header.X-Request-Id}")
        if not route.preserve_host:
            lines.append("\t\t\theader_up Host {upstream_hostport}")
        lines.extend(["\t\t}", "\t}", ""])
    lines.extend(["\trespond 404", "}", ""])
    return "\n".join(lines)


def render_summary(routes: list[Route], auth_exclude: str) -> dict[str, Any]:
    excludes = parse_auth_exclude(auth_exclude)
    return {
        "routes": [
            {
                "id": route.id,
                "match": route.match,
                "upstream": route.upstream,
                "auth": "excluded" if route_auth_excluded(route, excludes) else "required",
                "preserveHost": route.preserve_host,
            }
            for route in sort_routes(routes)
        ],
        "authExclude": {"paths": list(excludes.paths), "routes": list(excludes.route_ids), "ports": list(excludes.ports)},
    }
