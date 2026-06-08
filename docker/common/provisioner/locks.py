from __future__ import annotations

import json
import os
import shutil
import time
from pathlib import Path


class LockTimeout(RuntimeError):
    pass


class DirectoryLock:
    def __init__(self, path: Path, *, timeout_seconds: int = 60, poll_seconds: float = 1.0) -> None:
        self.path = path
        self.timeout_seconds = timeout_seconds
        self.poll_seconds = poll_seconds
        self.acquired = False

    def __enter__(self) -> "DirectoryLock":
        deadline = time.time() + self.timeout_seconds
        self.path.parent.mkdir(parents=True, exist_ok=True)
        while True:
            try:
                self.path.mkdir(mode=0o700)
                metadata = {
                    "pid": os.getpid(),
                    "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "hostname": os.uname().nodename if hasattr(os, "uname") else "unknown",
                }
                (self.path / "owner.json").write_text(json.dumps(metadata, sort_keys=True), encoding="utf-8")
                self.acquired = True
                return self
            except FileExistsError:
                if time.time() >= deadline:
                    raise LockTimeout(f"lock timeout: {self.path}")
                time.sleep(self.poll_seconds)

    def __exit__(self, exc_type, exc, tb) -> None:  # type: ignore[no-untyped-def]
        if self.acquired:
            shutil.rmtree(self.path, ignore_errors=True)
            self.acquired = False
