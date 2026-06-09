from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .config import env_path, load_data
from .inventory import load_inventory
from .locks import LockConflictError, commit, inspect, reap_expired, release, try_acquire
from .matcher import preflight
from .models import load_model_registry
from .reports import inspect_report
from .validation import run_fixture_validation


DEFAULT_MODELS = "configs/hil/model-requirements.yaml"
DEFAULT_SUITES = "configs/hil/hil-suites.yaml"
DEFAULT_INVENTORY = "configs/hil/fixture-gpu-inventory.yaml"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="xforce-hil")
    sub = parser.add_subparsers(dest="subcommand", required=True)

    validate = sub.add_parser("validate-config")
    validate.add_argument("--models", default=DEFAULT_MODELS)
    validate.add_argument("--suites", default=DEFAULT_SUITES)
    validate.add_argument("--inventory", default=DEFAULT_INVENTORY)

    pre = sub.add_parser("preflight")
    pre.add_argument("--model-id", required=True)
    pre.add_argument("--models", default=DEFAULT_MODELS)
    pre.add_argument("--inventory", default=DEFAULT_INVENTORY)
    pre.add_argument("--quantity", type=int, default=1)
    pre.add_argument("--max-price-per-hour", type=float)
    pre.add_argument("--allow-degraded", action="store_true")
    pre.add_argument("--request-id")

    book = sub.add_parser("book")
    book.add_argument("--model-id", required=True)
    book.add_argument("--request-id", required=True)
    book.add_argument("--models", default=DEFAULT_MODELS)
    book.add_argument("--inventory", default=DEFAULT_INVENTORY)
    book.add_argument("--lock-dir", default="/tmp/xforce-hil-locks")
    book.add_argument("--ttl", type=int, default=900)

    rel = sub.add_parser("release")
    rel.add_argument("--lock-id", required=True)
    rel.add_argument("--lock-dir", default="/tmp/xforce-hil-locks")

    com = sub.add_parser("commit")
    com.add_argument("--lock-id", required=True)
    com.add_argument("--booking-id", required=True)
    com.add_argument("--lock-dir", default="/tmp/xforce-hil-locks")

    ins = sub.add_parser("inspect-lock")
    ins.add_argument("--lock-id", required=True)
    ins.add_argument("--lock-dir", default="/tmp/xforce-hil-locks")

    reap = sub.add_parser("reap-expired")
    reap.add_argument("--lock-dir", default="/tmp/xforce-hil-locks")

    run = sub.add_parser("run-validation")
    run.add_argument("--suite-id", required=True)
    run.add_argument("--provider", default="fixture")
    run.add_argument("--node-id")
    run.add_argument("--suites", default=DEFAULT_SUITES)
    run.add_argument("--inventory", default=DEFAULT_INVENTORY)
    run.add_argument("--state-dir", default=str(env_path("XFORCE_HIL_STATE_DIR", "/tmp/xforce-ai/hil")))
    run.add_argument("--artifact-dir", default=str(env_path("XFORCE_HIL_ARTIFACT_DIR", "/tmp/xforce-ai/hil/artifacts")))
    run.add_argument("--fail-on-degraded", action="store_true")

    pub = sub.add_parser("publish-artifacts")
    pub.add_argument("--report", required=True)
    pub.add_argument("--publisher", default="local")
    pub.add_argument("--artifact-dir", default=str(env_path("XFORCE_HIL_ARTIFACT_DIR", "/tmp/xforce-ai/hil/artifacts")))

    report = sub.add_parser("inspect-report")
    report.add_argument("--report", required=True)

    return parser


def _print(payload: object) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


def _load_model(model_id: str, models_path: str):
    models = load_model_registry(load_data(models_path))
    if model_id not in models:
        raise KeyError(model_id)
    return models[model_id]


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.subcommand == "validate-config":
            models = load_model_registry(load_data(args.models))
            suites = load_data(args.suites).get("suites", [])
            inventory = load_inventory(load_data(args.inventory))
            _print({"status": "ok", "models": sorted(models), "suites": [item.get("suite_id") for item in suites], "inventoryDevices": len(inventory)})
            return 0
        if args.subcommand == "preflight":
            model = _load_model(args.model_id, args.models)
            result = preflight(model, load_inventory(load_data(args.inventory)), args.quantity, args.max_price_per_hour, args.allow_degraded, args.request_id)
            _print(result)
            return 0 if result["status"] == "available" else 3
        if args.subcommand == "book":
            model = _load_model(args.model_id, args.models)
            result = preflight(model, load_inventory(load_data(args.inventory)), 1, None, False, args.request_id)
            if not result["candidates"]:
                _print(result)
                return 3
            lock = try_acquire(Path(args.lock_dir), result["candidates"][0], args.request_id, args.model_id, args.ttl)
            _print(lock)
            return 0
        if args.subcommand == "release":
            _print(release(Path(args.lock_dir), args.lock_id))
            return 0
        if args.subcommand == "commit":
            _print(commit(Path(args.lock_dir), args.lock_id, args.booking_id))
            return 0
        if args.subcommand == "inspect-lock":
            _print(inspect(Path(args.lock_dir), args.lock_id))
            return 0
        if args.subcommand == "reap-expired":
            _print({"reaped": reap_expired(Path(args.lock_dir))})
            return 0
        if args.subcommand == "run-validation":
            if args.provider != "fixture":
                _print({"status": "provider_unavailable", "provider": args.provider})
                return 5
            _print(run_fixture_validation(Path(args.suites), Path(args.inventory), args.suite_id, args.node_id, Path(args.state_dir), Path(args.artifact_dir), args.fail_on_degraded))
            return 0
        if args.subcommand == "publish-artifacts":
            from .artifacts import publish_local

            if args.publisher != "local":
                _print({"status": "publisher_unavailable", "publisher": args.publisher})
                return 6
            _print(publish_local(load_data(args.report), Path(args.artifact_dir)))
            return 0
        if args.subcommand == "inspect-report":
            _print(inspect_report(Path(args.report)))
            return 0
    except LockConflictError as exc:
        _print({"error": "lock_conflict", "lock_id": str(exc)})
        return 4
    except (KeyError, ValueError) as exc:
        print(f"xforce-hil input error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"xforce-hil error: {exc}", file=sys.stderr)
        return 1
    return 2
