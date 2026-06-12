from __future__ import annotations

import hashlib
import json
import os
import queue
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@dataclass(frozen=True)
class IPFSConfig:
    enabled: bool
    api_url: str
    api_addr: str
    gateway_url: str
    public_gateway_enabled: bool
    public_gateway_url: str
    auto_roots: frozenset[str]
    auto_max_bytes: int
    state_path: Path
    repo: Path
    stable_seconds: float = 1.0
    request_timeout: float = 30.0


class IPFSBackupManager:
    def __init__(self, cfg: IPFSConfig) -> None:
        self.cfg = cfg
        self._lock = threading.RLock()
        self._jobs: dict[str, dict[str, Any]] = {}
        self._queued_keys: set[str] = set()
        self._queue: queue.Queue[dict[str, Any]] = queue.Queue()
        self._state = self._read_state()
        self._worker_started = False

    def start(self) -> None:
        if self._worker_started:
            return
        self._worker_started = True
        thread = threading.Thread(target=self._worker, name="xforce-ipfs-backup", daemon=True)
        thread.start()

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.cfg.enabled,
            "apiUrl": self.cfg.api_url,
            "gatewayUrlTemplate": self.cfg.gateway_url,
            "publicGatewayEnabled": self.cfg.public_gateway_enabled,
            "publicGatewayUrlTemplate": self.cfg.public_gateway_url,
            "autoRoots": sorted(self.cfg.auto_roots),
            "autoMaxBytes": self.cfg.auto_max_bytes,
            "statePath": str(self.cfg.state_path),
            "queueSize": self._queue.qsize(),
            "daemon": self._daemon_id(),
            "jobs": list(self._recent_jobs()),
        }

    def get_job(self, job_id: str) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return dict(job) if job else None

    def entry_status(self, root_name: str, rel_path: str, path: Path, *, auto: bool) -> dict[str, Any]:
        key = self._key(root_name, rel_path)
        if not self.cfg.enabled:
            return {"status": "disabled", "enabled": False}
        if not path.is_file():
            return {"status": "none"}
        stat = path.stat()
        record = self._record_for_file(key, stat.st_size, stat.st_mtime)
        if record:
            return self._public_record(record)
        if stat.st_size > self.cfg.auto_max_bytes and auto:
            return {"status": "manual_required", "autoMaxBytes": self.cfg.auto_max_bytes, "size": stat.st_size}
        if auto and root_name in self.cfg.auto_roots:
            job = self.enqueue(root_name, rel_path, path, manual=False, force=False)
            return {"status": "queued", "jobId": job["jobId"], "autoMaxBytes": self.cfg.auto_max_bytes}
        return {"status": "pending", "autoMaxBytes": self.cfg.auto_max_bytes}

    def enqueue(self, root_name: str, rel_path: str, path: Path, *, manual: bool, force: bool = False) -> dict[str, Any]:
        key = self._key(root_name, rel_path)
        stat = path.stat()
        with self._lock:
            if not force and key in self._queued_keys:
                for job in self._jobs.values():
                    if job.get("key") == key and job.get("status") in {"queued", "uploading"}:
                        return dict(job)
            job_id = f"ipfs-{uuid.uuid4().hex[:16]}"
            job = {
                "jobId": job_id,
                "key": key,
                "root": root_name,
                "path": rel_path,
                "absolutePath": str(path),
                "manual": manual,
                "force": force,
                "status": "queued",
                "size": stat.st_size,
                "modified": stat.st_mtime,
                "createdAt": utc_now(),
                "updatedAt": utc_now(),
            }
            self._jobs[job_id] = job
            self._queued_keys.add(key)
            self._queue.put(job)
            return dict(job)

    def _read_state(self) -> dict[str, Any]:
        try:
            if self.cfg.state_path.exists():
                data = json.loads(self.cfg.state_path.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
        return {}

    def _write_state(self) -> None:
        self.cfg.state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.cfg.state_path.with_suffix(self.cfg.state_path.suffix + ".tmp")
        tmp.write_text(json.dumps(self._state, indent=2, sort_keys=True), encoding="utf-8")
        os.replace(tmp, self.cfg.state_path)

    def _record_for_file(self, key: str, size: int, modified: float) -> dict[str, Any] | None:
        with self._lock:
            record = self._state.get(key)
            if not isinstance(record, dict):
                return None
            if int(record.get("size") or -1) != int(size):
                return None
            if abs(float(record.get("modified") or 0) - float(modified)) > 0.0001:
                return None
            return dict(record)

    def _public_record(self, record: dict[str, Any]) -> dict[str, Any]:
        cid = str(record.get("cid") or "")
        result = {key: value for key, value in record.items() if key not in {"absolutePath"}}
        if cid:
            result["gatewayUrl"] = self._format_gateway(self.cfg.gateway_url, cid)
            if self.cfg.public_gateway_enabled:
                result["publicGatewayUrl"] = self._format_gateway(self.cfg.public_gateway_url, cid)
            else:
                result.pop("publicGatewayUrl", None)
        return result

    def _worker(self) -> None:
        while True:
            job = self._queue.get()
            try:
                self._run_job(job)
            finally:
                with self._lock:
                    self._queued_keys.discard(str(job.get("key")))
                self._queue.task_done()

    def _run_job(self, job: dict[str, Any]) -> None:
        job_id = str(job["jobId"])
        path = Path(str(job["absolutePath"]))
        key = str(job["key"])
        self._update_job(job_id, status="uploading", updatedAt=utc_now())
        try:
            if not self.cfg.enabled:
                raise RuntimeError("IPFS backup is disabled")
            if not path.exists() or not path.is_file():
                raise RuntimeError("file does not exist")
            before = path.stat()
            time.sleep(max(self.cfg.stable_seconds, 0.0))
            after = path.stat()
            if before.st_size != after.st_size or before.st_mtime != after.st_mtime:
                raise RuntimeError("file is still changing; retry after generation completes")
            digest = sha256_file(path)
            cid = self._ipfs_add(path)
            record = {
                "root": job["root"],
                "path": job["path"],
                "status": "pinned",
                "cid": cid,
                "size": after.st_size,
                "modified": after.st_mtime,
                "sha256": digest,
                "gatewayUrl": self._format_gateway(self.cfg.gateway_url, cid),
                "updatedAt": utc_now(),
            }
            if self.cfg.public_gateway_enabled:
                record["publicGatewayUrl"] = self._format_gateway(self.cfg.public_gateway_url, cid)
            with self._lock:
                self._state[key] = record
                self._write_state()
            self._update_job(job_id, **record)
        except Exception as exc:  # noqa: BLE001
            record = {
                "root": job.get("root"),
                "path": job.get("path"),
                "status": "failed",
                "size": job.get("size"),
                "modified": job.get("modified"),
                "error": str(exc),
                "updatedAt": utc_now(),
            }
            with self._lock:
                self._state[key] = record
                self._write_state()
            self._update_job(job_id, **record)

    def _update_job(self, job_id: str, **values: Any) -> None:
        with self._lock:
            job = self._jobs.setdefault(job_id, {"jobId": job_id})
            job.update(values)

    def _recent_jobs(self) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(job) for job in list(self._jobs.values())[-20:]]

    def _daemon_id(self) -> dict[str, Any]:
        if not self.cfg.enabled:
            return {"ok": False, "status": "disabled"}
        try:
            data = self._post_json("/api/v0/id")
            return {"ok": True, "id": data.get("ID"), "addresses": data.get("Addresses", [])}
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc)}

    def _ipfs_add(self, path: Path) -> str:
        env = os.environ.copy()
        env["IPFS_PATH"] = str(self.cfg.repo)
        completed = subprocess.run(
            ["ipfs", f"--api={self.cfg.api_addr}", "add", "--pin=true", "--cid-version=1", "-Q", "--", str(path)],
            check=False,
            text=True,
            capture_output=True,
            timeout=max(self.cfg.request_timeout, 30.0),
            env=env,
        )
        if completed.returncode != 0:
            raise RuntimeError((completed.stderr or completed.stdout or "ipfs add failed").strip())
        cid = completed.stdout.strip().splitlines()[-1].strip() if completed.stdout.strip() else ""
        if not cid:
            raise RuntimeError("IPFS add did not return a CID")
        return cid

    def _post_json(self, path: str) -> dict[str, Any]:
        data = self._post_bytes(path, b"", "application/x-www-form-urlencoded")
        return json.loads(data.decode("utf-8")) if data else {}

    def _post_bytes(self, path: str, body: bytes, content_type: str) -> bytes:
        url = self.cfg.api_url.rstrip("/") + path
        request = urllib.request.Request(url, data=body, method="POST", headers={"content-type": content_type})
        try:
            with urllib.request.urlopen(request, timeout=self.cfg.request_timeout) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            text = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"IPFS API HTTP {exc.code}: {text}") from exc

    @staticmethod
    def _key(root_name: str, rel_path: str) -> str:
        rel = rel_path.strip().lstrip("/")
        return f"{root_name}/{rel}" if rel else root_name

    @staticmethod
    def _format_gateway(template: str, cid: str) -> str:
        if "{cid}" in template:
            return template.format(cid=cid)
        return template.rstrip("/") + f"/ipfs/{cid}"
