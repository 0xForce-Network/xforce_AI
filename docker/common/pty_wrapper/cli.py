from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .runner import run_command
from .state import WrapperContext


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-pty-wrap")
    sub = parser.add_subparsers(dest="subcommand", required=True)

    run = sub.add_parser("run")
    run.add_argument("--run-id")
    run.add_argument("--log-dir", default="/tmp/xforce-ai/pty")
    run.add_argument("--ansi-log")
    run.add_argument("--plain-log")
    run.add_argument("--state-dir")
    run.add_argument("--cwd")
    run.add_argument("--env", action="append", default=[])
    run.add_argument("--term", default="xterm-256color")
    run.add_argument("--cols", type=int, default=120)
    run.add_argument("--rows", type=int, default=40)
    run.add_argument("--no-console", action="store_true")
    run.add_argument("--terminate-timeout", type=float, default=10.0)
    run.add_argument("--kill-timeout", type=float, default=5.0)
    run.add_argument("--json", action="store_true")
    run.add_argument("command", nargs=argparse.REMAINDER)

    inspect = sub.add_parser("inspect")
    inspect.add_argument("--run-id", required=True)
    inspect.add_argument("--log-dir", default="/tmp/xforce-ai/pty")
    inspect.add_argument("--json", action="store_true")

    tail = sub.add_parser("tail")
    tail.add_argument("--run-id", required=True)
    tail.add_argument("--log-dir", default="/tmp/xforce-ai/pty")
    tail.add_argument("--stream", choices=("ansi", "plain"), default="plain")
    tail.add_argument("--lines", type=int, default=200)

    return parser


def _parse_env(values: list[str]) -> dict[str, str]:
    env: dict[str, str] = {}
    for item in values:
        if "=" not in item:
            raise ValueError(f"invalid --env value: {item}")
        key, value = item.split("=", 1)
        env[key] = value
    return env


def _run_command(args: argparse.Namespace) -> int:
    command = [item for item in args.command if item != "--"]
    if not command:
        raise ValueError("run requires a command after --")
    run_id = args.run_id or f"pty-{int(Path().stat().st_mtime_ns if hasattr(Path(), 'stat') else 0)}"
    ctx = WrapperContext(
        run_id=run_id,
        log_dir=Path(args.log_dir),
        state_dir=Path(args.state_dir) if args.state_dir else None,
        cwd=Path(args.cwd) if args.cwd else None,
        term=args.term,
        cols=args.cols,
        rows=args.rows,
        forward_console=not args.no_console,
        terminate_timeout=args.terminate_timeout,
        kill_timeout=args.kill_timeout,
        json_output=args.json,
        env_overrides=_parse_env(args.env),
    )
    result = run_command(ctx, command)
    if args.json:
        print(json.dumps(result.state.to_json(), sort_keys=True))
    return result.returncode


def _inspect_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.log_dir) / args.run_id
    state_file = run_dir / "state.json"
    if not state_file.exists():
        print(f"missing state: {state_file}", file=sys.stderr)
        return 1
    print(state_file.read_text(encoding="utf-8"), end="")
    return 0


def _tail_command(args: argparse.Namespace) -> int:
    run_dir = Path(args.log_dir) / args.run_id
    log_file = run_dir / ("stdout.ansi.log" if args.stream == "ansi" else "stdout.plain.log")
    if not log_file.exists():
        print(f"missing log: {log_file}", file=sys.stderr)
        return 1
    data = log_file.read_text(encoding="utf-8", errors="replace")
    lines = data.splitlines()[-args.lines :]
    print("\n".join(lines))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.subcommand == "run":
            return _run_command(args)
        if args.subcommand == "inspect":
            return _inspect_command(args)
        if args.subcommand == "tail":
            return _tail_command(args)
    except Exception as exc:  # noqa: BLE001
        print(f"pty wrapper error: {exc}", file=sys.stderr)
        return 1
    return 2
