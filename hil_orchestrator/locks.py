from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
from typing import Any

from .config import write_json


class LockConflictError(RuntimeError):
    pass


def _lock_id(node_id: str, device_fingerprint: str) -> str:
    digest = hashlib.sha256(f"{node_id}:{device_fingerprint}".encode()).hexdigest()[:16]
    return f"lock-{digest}"


def _path(lock_dir: Path, lock_id: str) -> Path:
    return lock_dir / f"{lock_id}.json"


def _now() -> dt.datetime:
    return dt.datetime.now(dt.UTC).replace(microsecond=0)


def _iso(value: dt.datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _expired(payload: dict[str, Any]) -> bool:
    expires = str(payload.get("expires_at") or "")
    try:
        return dt.datetime.fromisoformat(expires.replace("Z", "+00:00")) <= _now()
    except ValueError:
        return True


def try_acquire(lock_dir: Path, candidate: dict[str, Any], request_id: str, model_id: str, ttl_seconds: int = 900, owner: str = "scheduler") -> dict[str, Any]:
    lock_dir.mkdir(parents=True, exist_ok=True)
    node_id = str(candidate["node_id"])
    device_fingerprint = str(candidate["device_fingerprint"])
    lock_id = _lock_id(node_id, device_fingerprint)
    path = _path(lock_dir, lock_id)
    if path.exists():
        payload = json.loads(path.read_text(encoding="utf-8"))
        if _expired(payload):
            path.unlink()
        elif payload.get("request_id") == request_id:
            return payload
        else:
            raise LockConflictError(lock_id)
    now = _now()
    payload = {
        "lock_id": lock_id,
        "booking_id": "",
        "request_id": request_id,
        "model_id": model_id,
        "node_id": node_id,
        "device_fingerprint": device_fingerprint,
        "owner": owner,
        "created_at": _iso(now),
        "expires_at": _iso(now + dt.timedelta(seconds=ttl_seconds)),
        "state": "held",
    }
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return payload


def inspect(lock_dir: Path, lock_id: str) -> dict[str, Any]:
    return json.loads(_path(lock_dir, lock_id).read_text(encoding="utf-8"))


def commit(lock_dir: Path, lock_id: str, booking_id: str) -> dict[str, Any]:
    payload = inspect(lock_dir, lock_id)
    payload["booking_id"] = booking_id
    payload["state"] = "committed"
    write_json(_path(lock_dir, lock_id), payload)
    return payload


def release(lock_dir: Path, lock_id: str) -> dict[str, Any]:
    payload = inspect(lock_dir, lock_id)
    payload["state"] = "released"
    _path(lock_dir, lock_id).unlink(missing_ok=True)
    return payload


def reap_expired(lock_dir: Path) -> int:
    count = 0
    if not lock_dir.exists():
        return count
    for path in lock_dir.glob("lock-*.json"):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if _expired(payload):
            path.unlink(missing_ok=True)
            count += 1
    return count
