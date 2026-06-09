from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from .config import TunnelConfig
from .named import run_named
from .quick import quick_command, run_quick
from .state import read_state


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-tunnel")
    sub = parser.add_subparsers(dest="subcommand", required=True)
    for name in ("quick", "named", "auto", "status", "command"):
        cmd = sub.add_parser(name)
        cmd.add_argument("--url")
        cmd.add_argument("--metrics")
        cmd.add_argument("--token-env")
        cmd.add_argument("--cloudflared-bin")
        cmd.add_argument("--state-dir")
        cmd.add_argument("--dry-run", action="store_true")
        cmd.add_argument("--json", action="store_true")
    return parser


def _cfg(args: argparse.Namespace) -> TunnelConfig:
    base = TunnelConfig.from_env()
    return TunnelConfig(
        url=args.url or base.url,
        metrics=args.metrics or base.metrics,
        token_env=args.token_env or base.token_env,
        cloudflared_bin=args.cloudflared_bin or base.cloudflared_bin,
        state_dir=Path(args.state_dir) if args.state_dir else base.state_dir,
        mode=base.mode,
    )


def _print(payload: object, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, sort_keys=True))
    else:
        print(payload if isinstance(payload, str) else json.dumps(payload, sort_keys=True))


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    cfg = _cfg(args)
    if args.subcommand == "status":
        _print(read_state(cfg.state_dir), args.json)
        return 0
    if args.subcommand == "command":
        token = os.environ.get(cfg.token_env, "")
        if token:
            payload = {"mode": "named", "command": [cfg.cloudflared_bin, "tunnel", "run", "--token", "***MASKED***", "--metrics", cfg.metrics]}
        else:
            payload = {"mode": "quick", "command": quick_command(cfg)}
        _print(payload, args.json)
        return 0
    if args.subcommand == "quick":
        _print(run_quick(cfg, args.dry_run), args.json)
        return 0
    if args.subcommand == "named":
        _print(run_named(cfg, args.dry_run), args.json)
        return 0
    if args.subcommand == "auto":
        mode = cfg.mode
        if mode in {"0", "false", "FALSE", "no", "NO", "off", "OFF"}:
            payload = {"mode": "auto", "status": "disabled"}
            from .state import write_state

            write_state(cfg.state_dir, payload)
            _print(payload, args.json)
            return 0
        if os.environ.get(cfg.token_env):
            _print(run_named(cfg, args.dry_run), args.json)
            return 0
        if mode == "quick":
            _print(run_quick(cfg, args.dry_run), args.json)
            return 0
        payload = {"mode": "auto", "status": "skipped", "reason": "token_missing_quick_not_requested"}
        from .state import write_state

        write_state(cfg.state_dir, payload)
        _print(payload, args.json)
        return 0
    return 2
