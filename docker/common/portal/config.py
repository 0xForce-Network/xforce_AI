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
    file_roots: str = "outputs:/workspace/outputs"
    ipfs_enabled: bool = True
    ipfs_api_url: str = "http://127.0.0.1:5001"
    ipfs_api_addr: str = "/ip4/127.0.0.1/tcp/5001"
    ipfs_gateway_url: str = "/ipfs/{cid}"
    ipfs_public_gateway_enabled: bool = False
    ipfs_public_gateway_url: str = "https://ipfs.io/ipfs/{cid}"
    ipfs_auto_roots: str = "outputs"
    ipfs_auto_max_bytes: int = 1073741824
    ipfs_state_path: Path = Path("/workspace/.xforce-ipfs/backup-index.json")
    ipfs_repo: Path = Path("/workspace/.xforce-ipfs/repo")
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
            file_roots=os.environ.get("XFORCE_FILE_ROOTS", "outputs:/workspace/outputs"),
            ipfs_enabled=os.environ.get("XFORCE_IPFS_ENABLED", "1") not in {"0", "false", "False", "no", "NO"},
            ipfs_api_url=os.environ.get("XFORCE_IPFS_API_URL", "http://127.0.0.1:5001"),
            ipfs_api_addr=os.environ.get("XFORCE_IPFS_API_ADDR", "/ip4/127.0.0.1/tcp/5001"),
            ipfs_gateway_url=os.environ.get("XFORCE_IPFS_GATEWAY_URL", "/ipfs/{cid}"),
            ipfs_public_gateway_enabled=os.environ.get("XFORCE_IPFS_PUBLIC_GATEWAY_ENABLED", "0")
            not in {"0", "false", "False", "no", "NO"},
            ipfs_public_gateway_url=os.environ.get("XFORCE_IPFS_PUBLIC_GATEWAY_URL", "https://ipfs.io/ipfs/{cid}"),
            ipfs_auto_roots=os.environ.get("XFORCE_IPFS_AUTO_ROOTS", "outputs"),
            ipfs_auto_max_bytes=_int_env("XFORCE_IPFS_AUTO_MAX_BYTES", 1073741824),
            ipfs_state_path=_path_env("XFORCE_IPFS_STATE_PATH", "/workspace/.xforce-ipfs/backup-index.json"),
            ipfs_repo=_path_env("XFORCE_IPFS_REPO", "/workspace/.xforce-ipfs/repo"),
            default_log_limit=_int_env("XFORCE_LOG_DEFAULT_LIMIT", 65536),
            max_log_limit=_int_env("XFORCE_LOG_MAX_LIMIT", 1048576),
        )
