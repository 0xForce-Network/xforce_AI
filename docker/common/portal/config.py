from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _path_env(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default))


def _int_env(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


@dataclass(frozen=True)
class PortalConfig:
    portal_host: str = "127.0.0.1"
    portal_port: int = 8080
    supervisor_socket: Path = Path("/tmp/xforce-ai/supervisor/supervisor.sock")
    supervisor_config: Path = Path("/etc/supervisor/supervisord.conf")
    service_registry: Path = Path("/etc/xforce-ai/services.yaml")
    service_log_dir: Path = Path("/tmp/xforce-ai/services")
    pty_log_dir: Path = Path("/tmp/xforce-ai/pty")
    metrics_state_dir: Path = Path("/tmp/xforce-ai/metrics")
    cgroup_root: Path = Path("/sys/fs/cgroup")
    default_log_limit: int = 65536
    max_log_limit: int = 1048576

    @classmethod
    def from_env(cls) -> "PortalConfig":
        return cls(
            portal_host=os.environ.get("XFORCE_PORTAL_HOST", "127.0.0.1"),
            portal_port=_int_env("XFORCE_PORTAL_PORT", 8080),
            supervisor_socket=_path_env("XFORCE_SUPERVISOR_SOCKET", "/tmp/xforce-ai/supervisor/supervisor.sock"),
            supervisor_config=_path_env("XFORCE_SUPERVISOR_CONFIG", "/etc/supervisor/supervisord.conf"),
            service_registry=_path_env("XFORCE_SERVICE_REGISTRY", "/etc/xforce-ai/services.yaml"),
            service_log_dir=_path_env("XFORCE_SERVICE_LOG_DIR", "/tmp/xforce-ai/services"),
            pty_log_dir=_path_env("XFORCE_PTY_LOG_DIR", "/tmp/xforce-ai/pty"),
            metrics_state_dir=_path_env("XFORCE_METRICS_STATE_DIR", "/tmp/xforce-ai/metrics"),
            cgroup_root=_path_env("XFORCE_CGROUP_ROOT", "/sys/fs/cgroup"),
            default_log_limit=_int_env("XFORCE_LOG_DEFAULT_LIMIT", 65536),
            max_log_limit=_int_env("XFORCE_LOG_MAX_LIMIT", 1048576),
        )
