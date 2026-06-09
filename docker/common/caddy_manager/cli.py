from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from .auth import AuthConfig
from .config import CaddyManagerConfig
from .render import render_caddyfile, render_summary
from .routes import load_routes
from .state import write_env


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-caddy")
    sub = parser.add_subparsers(dest="subcommand", required=True)
    for name in ("render", "validate", "reload", "show"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--routes")
        cmd.add_argument("--auth")
        cmd.add_argument("--output")
        cmd.add_argument("--caddy-bin")
        cmd.add_argument("--dry-run", action="store_true")
        cmd.add_argument("--json", action="store_true")
    return parser


def _cfg(args: argparse.Namespace) -> CaddyManagerConfig:
    base = CaddyManagerConfig.from_env()
    return CaddyManagerConfig(
        http_addr=base.http_addr,
        admin_addr=base.admin_addr,
        routes_path=Path(args.routes) if args.routes else base.routes_path,
        auth_path=Path(args.auth) if args.auth else base.auth_path,
        output_path=Path(args.output) if args.output else base.output_path,
        caddy_bin=args.caddy_bin or base.caddy_bin,
        portal_upstream=base.portal_upstream,
        auth_exclude=base.auth_exclude,
    )


def _render(cfg: CaddyManagerConfig) -> str:
    routes = load_routes(cfg.routes_path, cfg.portal_upstream)
    return render_caddyfile(routes, cfg.http_addr, cfg.admin_addr, cfg.auth_exclude)


def _render_write(cfg: CaddyManagerConfig) -> dict[str, object]:
    caddyfile = _render(cfg)
    cfg.output_path.parent.mkdir(parents=True, exist_ok=True)
    cfg.output_path.write_text(caddyfile, encoding="utf-8")
    routes = load_routes(cfg.routes_path, cfg.portal_upstream)
    write_env(
        Path("/tmp/xforce-ai/caddy/caddy.env"),
        {
            "XFORCE_CADDY_STATUS": "rendered",
            "XFORCE_CADDY_CONFIG": str(cfg.output_path),
            "XFORCE_CADDY_HTTP_ADDR": cfg.http_addr,
            "XFORCE_CADDY_AUTH_TOKEN_CONFIGURED": str(bool(AuthConfig.from_yaml_env(cfg.auth_path).token)).lower(),
        },
    )
    return {"output": str(cfg.output_path), **render_summary(routes, cfg.auth_exclude)}


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    cfg = _cfg(args)
    try:
        if args.subcommand == "render":
            result = _render_write(cfg)
            if args.json:
                print(json.dumps(result, sort_keys=True))
            else:
                print(result["output"])
            return 0
        if args.subcommand == "show":
            print(_render(cfg), end="")
            return 0
        if args.subcommand == "validate":
            if not cfg.output_path.exists():
                _render_write(cfg)
            if args.dry_run:
                print(json.dumps({"valid": True, "dryRun": True, "config": str(cfg.output_path)}, sort_keys=True) if args.json else "valid dry-run")
                return 0
            proc = subprocess.run([cfg.caddy_bin, "validate", "--config", str(cfg.output_path), "--adapter", "caddyfile"], check=False)
            return proc.returncode
        if args.subcommand == "reload":
            if not cfg.output_path.exists():
                _render_write(cfg)
            if args.dry_run:
                print(json.dumps({"reloaded": False, "dryRun": True, "config": str(cfg.output_path)}, sort_keys=True) if args.json else "reload dry-run")
                return 0
            proc = subprocess.run([cfg.caddy_bin, "reload", "--config", str(cfg.output_path), "--adapter", "caddyfile"], check=False)
            return proc.returncode
    except Exception as exc:  # noqa: BLE001
        print(f"xforce-caddy error: {exc}", file=sys.stderr)
        return 1
    return 2
