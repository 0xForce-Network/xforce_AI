from __future__ import annotations

import argparse

import uvicorn

from .config import PortalConfig


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-portal")
    sub = parser.add_subparsers(dest="subcommand")

    serve = sub.add_parser("serve", help="run the local portal backend")
    serve.add_argument("--host", default=None)
    serve.add_argument("--port", type=int, default=None)
    serve.add_argument("--log-level", default="info")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    subcommand = args.subcommand or "serve"
    if subcommand == "serve":
        cfg = PortalConfig.from_env()
        host = getattr(args, "host", None) or cfg.portal_host
        port = getattr(args, "port", None) or cfg.portal_port
        log_level = getattr(args, "log_level", "info")
        uvicorn.run("portal.app:create_app", host=host, port=port, factory=True, log_level=log_level)
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
