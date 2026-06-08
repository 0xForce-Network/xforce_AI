from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from .manifest import ManifestError, load_manifest, manifest_name, validate_manifest
from .state import ProvisionContext, read_stage_state, stage_hash, stage_key, write_stage_state, write_summary
from .stages import run_stage


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-provision")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["run", "validate", "plan"]:
        cmd = sub.add_parser(name)
        cmd.add_argument("--manifest", required=True)
        cmd.add_argument("--state-dir")
        cmd.add_argument("--cache-dir")
        cmd.add_argument("--workspace-dir")
        cmd.add_argument("--venv-dir")
        cmd.add_argument("--dry-run", action="store_true")
        cmd.add_argument("--force", action="store_true")
        cmd.add_argument("--stage")
        cmd.add_argument("--no-retry", action="store_true")
        cmd.add_argument("--json", action="store_true")
    state = sub.add_parser("state")
    state_sub = state.add_subparsers(dest="state_command", required=True)
    state_list = state_sub.add_parser("list")
    state_list.add_argument("--state-dir")
    state_show = state_sub.add_parser("show")
    state_show.add_argument("stage_id")
    state_show.add_argument("--state-dir")
    return parser


def _load(args: argparse.Namespace, ctx: ProvisionContext) -> tuple[dict[str, Any], str, str]:
    manifest, source_type = load_manifest(args.manifest, ctx)
    name = manifest_name(manifest, args.manifest)
    return manifest, source_type, name


def command_validate(args: argparse.Namespace) -> int:
    ctx = ProvisionContext.from_env(args)
    ctx.ensure_dirs()
    manifest, source_type, name = _load(args, ctx)
    result = {"status": "valid", "name": name, "source": source_type, "stages": len(manifest["stages"])}
    if args.json:
        print(json.dumps(result, sort_keys=True))
    else:
        print(f"valid manifest name={name} stages={len(manifest['stages'])}")
    return 0


def plan_stages(args: argparse.Namespace, ctx: ProvisionContext, manifest: dict[str, Any], name: str) -> list[dict[str, Any]]:
    plan: list[dict[str, Any]] = []
    for stage in manifest["stages"]:
        if args.stage and stage["id"] != args.stage:
            continue
        digest = stage_hash(ctx, stage)
        existing = read_stage_state(ctx, name, stage["id"])
        status = "run"
        if existing and existing.get("status") == "complete" and existing.get("stageHash") == digest and not args.force:
            status = "skip"
        plan.append({"id": stage["id"], "type": stage["type"], "hash": digest, "status": status})
    return plan


def command_plan(args: argparse.Namespace) -> int:
    ctx = ProvisionContext.from_env(args)
    ctx.ensure_dirs()
    manifest, _source_type, name = _load(args, ctx)
    plan = plan_stages(args, ctx, manifest, name)
    if args.json:
        print(json.dumps(plan, sort_keys=True))
    else:
        for item in plan:
            print(f"{item['status']} {item['type']} {item['id']} {item['hash']}")
    return 0


def command_run(args: argparse.Namespace) -> int:
    ctx = ProvisionContext.from_env(args)
    ctx.ensure_dirs()
    manifest, source_type, name = _load(args, ctx)
    selected = [stage for stage in manifest["stages"] if not args.stage or stage["id"] == args.stage]
    completed = 0
    skipped = 0
    failed = 0
    write_summary(ctx, status="running", manifest=args.manifest, manifest_source=source_type, total=len(selected))
    for stage in selected:
        digest = stage_hash(ctx, stage)
        existing = read_stage_state(ctx, name, stage["id"])
        if existing and existing.get("status") == "complete" and existing.get("stageHash") == digest and not args.force:
            skipped += 1
            continue
        try:
            outputs = run_stage(ctx, stage)
            write_stage_state(ctx, name, stage, "complete", digest, attempts=1, outputs=outputs)
            completed += 1
        except Exception as exc:  # noqa: BLE001
            failed += 1
            write_stage_state(ctx, name, stage, "failed", digest, attempts=1, error=str(exc))
            write_summary(ctx, status="failed", manifest=args.manifest, manifest_source=source_type, total=len(selected), completed=completed, skipped=skipped, failed=failed, last_error=str(exc))
            raise
    write_summary(ctx, status="complete", manifest=args.manifest, manifest_source=source_type, total=len(selected), completed=completed, skipped=skipped, failed=failed)
    if args.json:
        print(json.dumps({"status": "complete", "completed": completed, "skipped": skipped, "failed": failed}, sort_keys=True))
    else:
        print(f"provision complete completed={completed} skipped={skipped} failed={failed}")
    return 0


def command_state(args: argparse.Namespace) -> int:
    from pathlib import Path

    ctx = ProvisionContext.from_env(args)
    stage_dir = ctx.state_dir / "stages"
    if args.state_command == "list":
        for path in sorted(stage_dir.glob("*.json")):
            print(path.stem)
        return 0
    safe = stage_key("", args.stage_id)
    candidates = list(stage_dir.glob(f"*{safe}*.json")) + [stage_dir / f"{args.stage_id}.json"]
    for path in candidates:
        if Path(path).exists():
            print(Path(path).read_text(encoding="utf-8"))
            return 0
    print(f"stage state not found: {args.stage_id}", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "validate":
            return command_validate(args)
        if args.command == "plan":
            return command_plan(args)
        if args.command == "run":
            return command_run(args)
        if args.command == "state":
            return command_state(args)
    except ManifestError as exc:
        print(f"manifest error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"provision error: {exc}", file=sys.stderr)
        return 1
    return 2
