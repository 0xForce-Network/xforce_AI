from __future__ import annotations

from pathlib import Path
from typing import Any

import xmlrpc.client
import yaml
from fastapi import FastAPI, Query, Request, Response
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse

from caddy_manager.auth import AuthConfig, sign_cookie, token_matches, verify_cookie

from . import API_VERSION, PORTAL_VERSION
from .config import PortalConfig
from .files import FileBrowserError, list_dir_page, parse_file_roots, safe_child
from .ipfs import IPFSBackupManager, IPFSConfig
from .logs import read_service_log
from .metrics.cpu import read_cpu_metrics
from .metrics.gpu import read_gpu_metrics
from .metrics.memory import read_memory_metrics
from .services import ServiceRegistry, merge_status
from .supervisor_client import SupervisorClient


class PortalError(Exception):
    def __init__(self, status_code: int, error: str, message: str) -> None:
        self.status_code = status_code
        self.error = error
        self.message = message


def _error(status_code: int, error: str, message: str) -> None:
    raise PortalError(status_code, error, message)


def _process_map(client: SupervisorClient) -> dict[str, dict[str, Any]]:
    if not client.available:
        return {}
    try:
        return {item.get("name", ""): item for item in client.get_all_process_info()}
    except Exception:  # noqa: BLE001
        return {}


def create_app() -> FastAPI:
    cfg = PortalConfig.from_env()
    registry = ServiceRegistry.load(cfg.service_registry)
    supervisor = SupervisorClient(cfg.supervisor_socket)
    file_roots = parse_file_roots(cfg.file_roots)
    ipfs = IPFSBackupManager(
        IPFSConfig(
            enabled=cfg.ipfs_enabled,
            api_url=cfg.ipfs_api_url,
            api_addr=cfg.ipfs_api_addr,
            gateway_url=cfg.ipfs_gateway_url,
            public_gateway_enabled=cfg.ipfs_public_gateway_enabled,
            public_gateway_url=cfg.ipfs_public_gateway_url,
            auto_roots=frozenset(item.strip().lower() for item in cfg.ipfs_auto_roots.split(",") if item.strip()),
            auto_max_bytes=cfg.ipfs_auto_max_bytes,
            state_path=cfg.ipfs_state_path,
            repo=cfg.ipfs_repo,
        )
    )
    ipfs.start()
    app = FastAPI(title="xforce_AI Instance Portal Backend", version=PORTAL_VERSION)

    def _auth_cfg() -> AuthConfig:
        return AuthConfig.from_yaml_env(Path("/etc/xforce-ai/caddy/auth.yaml"))

    @app.exception_handler(PortalError)
    async def portal_error_handler(_request: Request, exc: PortalError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content={"error": exc.error, "message": exc.message})

    @app.exception_handler(FileBrowserError)
    async def file_browser_error_handler(_request: Request, exc: FileBrowserError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content={"error": exc.error, "message": exc.message})

    @app.get("/api/v1/portal-assets/{asset_name}")
    def portal_asset(asset_name: str) -> FileResponse:
        if asset_name != "file-browser.js":
            _error(404, "asset_not_found", "portal asset is not available")
        path = Path(__file__).resolve().parent / "static" / asset_name
        if not path.exists():
            _error(404, "asset_not_found", "portal asset is missing")
        return FileResponse(path, media_type="application/javascript")

    @app.get("/api/v1/health")
    def health() -> dict[str, Any]:
        return {
            "status": "ok",
            "apiVersion": API_VERSION,
            "supervisor": {"available": supervisor.ping(), "socket": str(cfg.supervisor_socket)},
        }

    @app.get("/api/v1/version")
    def version() -> dict[str, str]:
        return {"apiVersion": API_VERSION, "portalVersion": PORTAL_VERSION}

    @app.api_route("/api/v1/auth/check", methods=["GET", "POST", "HEAD"])
    def auth_check(request: Request) -> Response:
        auth_cfg = _auth_cfg()
        if not auth_cfg.token:
            return Response(status_code=204)
        authorization = request.headers.get("authorization", "")
        bearer = authorization.removeprefix("Bearer ").strip() if authorization.lower().startswith("bearer ") else None
        header_token = request.headers.get(auth_cfg.header_name)
        query_token = request.query_params.get(auth_cfg.query_name)
        cookie_value = request.cookies.get(auth_cfg.cookie_name)
        if auth_cfg.bearer_enabled and token_matches(bearer, auth_cfg):
            return Response(status_code=204)
        if token_matches(header_token, auth_cfg):
            return Response(status_code=204)
        if verify_cookie(cookie_value or "", auth_cfg.token, auth_cfg.cookie_secret, auth_cfg.cookie_ttl_seconds):
            return Response(status_code=204)
        if token_matches(query_token, auth_cfg):
            cookie = sign_cookie(auth_cfg.token, auth_cfg.cookie_secret)
            clean_url = str(request.url.include_query_params(**{auth_cfg.query_name: ""})).replace(f"{auth_cfg.query_name}=", "")
            response = RedirectResponse(clean_url, status_code=303)
            response.set_cookie(auth_cfg.cookie_name, cookie, httponly=True, samesite="lax", max_age=auth_cfg.cookie_ttl_seconds)
            return response
        return JSONResponse(status_code=401, content={"error": "unauthorized", "message": "valid xforce auth token is required"})

    @app.get("/api/v1/services")
    def list_services() -> dict[str, Any]:
        processes = _process_map(supervisor)
        services = [merge_status(spec, processes.get(spec.supervisor_name)) for spec in registry.all()]
        return {"services": services}

    @app.get("/api/v1/services/{service_name}")
    def get_service(service_name: str) -> dict[str, Any]:
        spec = registry.get(service_name)
        if not spec:
            _error(404, "unknown_service", "service is not registered")
        processes = _process_map(supervisor)
        return merge_status(spec, processes.get(spec.supervisor_name))

    def _lifecycle(service_name: str, action: str) -> dict[str, Any]:
        spec = registry.get(service_name)
        if not spec:
            _error(404, "unknown_service", "service is not registered")
        if spec.protected and action in {"stop", "restart"}:
            _error(403, "protected_service", "service is protected and cannot be stopped through Portal API")
        if not supervisor.available:
            _error(503, "supervisor_unavailable", "Supervisor XML-RPC socket is not available")
        try:
            if action == "start":
                supervisor.start(spec.supervisor_name)
            elif action == "stop":
                supervisor.stop(spec.supervisor_name)
            elif action == "restart":
                try:
                    info = supervisor.get_process_info(spec.supervisor_name)
                    if info.get("statename") == "RUNNING":
                        supervisor.stop(spec.supervisor_name)
                except xmlrpc.client.Fault:
                    pass
                supervisor.start(spec.supervisor_name)
        except xmlrpc.client.Fault as exc:
            _error(409, "supervisor_fault", str(exc.faultString))
        except Exception as exc:  # noqa: BLE001
            _error(503, "supervisor_error", str(exc))
        return merge_status(spec, supervisor.get_process_info(spec.supervisor_name))

    @app.post("/api/v1/services/{service_name}/start")
    def start_service(service_name: str) -> dict[str, Any]:
        return _lifecycle(service_name, "start")

    @app.post("/api/v1/services/{service_name}/stop")
    def stop_service(service_name: str) -> dict[str, Any]:
        return _lifecycle(service_name, "stop")

    @app.post("/api/v1/services/{service_name}/restart")
    def restart_service(service_name: str) -> dict[str, Any]:
        return _lifecycle(service_name, "restart")

    @app.get("/api/v1/services/{service_name}/logs")
    def get_logs(
        service_name: str,
        stream: str = Query(default="stdout"),
        offset: int = Query(default=0, ge=0),
        limit: int = Query(default=65536, ge=0),
    ) -> dict[str, Any]:
        spec = registry.get(service_name)
        if not spec:
            _error(404, "unknown_service", "service is not registered")
        try:
            return read_service_log(cfg, spec, stream, offset, limit)
        except KeyError:
            _error(400, "invalid_log_stream", "requested log stream is not available for this service")
        except PermissionError as exc:
            _error(403, "log_path_denied", str(exc))

    @app.get("/api/v1/metrics/cpu")
    def cpu_metrics() -> dict[str, Any]:
        return read_cpu_metrics(cfg.cgroup_root)

    @app.get("/api/v1/metrics/memory")
    def memory_metrics() -> dict[str, Any]:
        return read_memory_metrics(cfg.cgroup_root)

    @app.get("/api/v1/metrics/gpu")
    def gpu_metrics() -> dict[str, Any]:
        return read_gpu_metrics()

    @app.get("/api/v1/metrics")
    def metrics() -> dict[str, Any]:
        return {"cpu": read_cpu_metrics(cfg.cgroup_root), "memory": read_memory_metrics(cfg.cgroup_root), "gpu": read_gpu_metrics()}

    @app.get("/api/v1/proxy/routes")
    def proxy_routes() -> dict[str, Any]:
        path = Path("/etc/xforce-ai/caddy/routes.yaml")
        if not path.exists():
            return {"routes": []}
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        return {"apiVersion": data.get("apiVersion", "xforce.ai/routes/v1"), "routes": data.get("routes", [])}

    @app.get("/api/v1/proxy/auth")
    def proxy_auth() -> dict[str, Any]:
        return _auth_cfg().masked()

    def _ipfs_lookup(root: Any, path: Path, *, auto: bool) -> dict[str, Any]:
        rel = "" if path == root.path else path.relative_to(root.path).as_posix()
        return ipfs.entry_status(root.name, rel, path, auto=auto)

    @app.get("/api/v1/files")
    def api_list_roots() -> dict[str, Any]:
        return {"roots": [{"name": root.name, "path": str(root.path)} for root in file_roots.values()]}

    @app.get("/api/v1/files/{root_name}")
    def api_list_root(root_name: str, page: int = Query(default=1), pageSize: int = Query(default=15), search: str = Query(default=""), sort: str = Query(default="name"), order: str = Query(default="asc")) -> dict[str, Any]:
        root = file_roots.get(root_name.lower())
        if not root:
            _error(404, "unknown_root", "file root is not configured")
        return list_dir_page(root.path, root, page=page, page_size=pageSize, search=search, sort=sort, order=order, ipfs_lookup=_ipfs_lookup)

    @app.get("/api/v1/files/{root_name}/{rel_path:path}")
    def api_get_file(root_name: str, rel_path: str, download: bool = Query(default=False), page: int = Query(default=1), pageSize: int = Query(default=15), search: str = Query(default=""), sort: str = Query(default="name"), order: str = Query(default="asc")) -> Any:
        root = file_roots.get(root_name.lower())
        if not root:
            _error(404, "unknown_root", "file root is not configured")
        path = safe_child(root, rel_path)
        if not path.exists():
            _error(404, "not_found", "path does not exist")
        if path.is_dir() and not download:
            return list_dir_page(path, root, page=page, page_size=pageSize, search=search, sort=sort, order=order, ipfs_lookup=_ipfs_lookup)
        if path.is_dir():
            _error(400, "directory_download_denied", "directory download is not supported")
        return FileResponse(path, filename=path.name if download else None)

    @app.get("/files/")
    def list_roots() -> dict[str, Any]:
        return api_list_roots()

    @app.get("/files/{root_name}")
    def list_root(root_name: str, page: int = Query(default=1), pageSize: int = Query(default=15), search: str = Query(default=""), sort: str = Query(default="name"), order: str = Query(default="asc")) -> dict[str, Any]:
        return api_list_root(root_name, page=page, pageSize=pageSize, search=search, sort=sort, order=order)

    @app.get("/files/{root_name}/{rel_path:path}")
    def get_file(root_name: str, rel_path: str, download: bool = Query(default=False), page: int = Query(default=1), pageSize: int = Query(default=15), search: str = Query(default=""), sort: str = Query(default="name"), order: str = Query(default="asc")) -> Any:
        return api_get_file(root_name, rel_path, download=download, page=page, pageSize=pageSize, search=search, sort=sort, order=order)

    @app.get("/api/v1/ipfs/status")
    def ipfs_status() -> dict[str, Any]:
        return ipfs.status()

    @app.get("/api/v1/ipfs/jobs/{job_id}")
    def ipfs_job(job_id: str) -> dict[str, Any]:
        job = ipfs.get_job(job_id)
        if not job:
            _error(404, "unknown_ipfs_job", "IPFS backup job was not found")
        return job

    @app.post("/api/v1/ipfs/backup")
    async def ipfs_backup(request: Request) -> dict[str, Any]:
        payload = await request.json()
        root_name = str(payload.get("root") or "").strip().lower()
        rel_path = str(payload.get("path") or "").strip()
        force = bool(payload.get("force") or False)
        root = file_roots.get(root_name)
        if not root:
            _error(404, "unknown_root", "file root is not configured")
        path = safe_child(root, rel_path)
        if not path.exists() or not path.is_file():
            _error(404, "not_found", "file does not exist")
        return ipfs.enqueue(root.name, path.relative_to(root.path).as_posix(), path, manual=True, force=force)

    @app.post("/api/v1/ipfs/retry")
    async def ipfs_retry(request: Request) -> dict[str, Any]:
        return await ipfs_backup(request)

    @app.get("/api/v1/tunnel/status")
    def tunnel_status() -> dict[str, Any]:
        state_path = Path("/tmp/xforce-ai/tunnel/state.json")
        if not state_path.exists():
            return {"status": "missing"}
        return yaml.safe_load(state_path.read_text(encoding="utf-8")) or {"status": "missing"}

    @app.post("/api/v1/tunnel/start")
    def tunnel_start() -> dict[str, Any]:
        return _lifecycle("cloudflared", "start")

    @app.post("/api/v1/tunnel/stop")
    def tunnel_stop() -> dict[str, Any]:
        return _lifecycle("cloudflared", "stop")

    @app.post("/api/v1/tunnel/restart")
    def tunnel_restart() -> dict[str, Any]:
        return _lifecycle("cloudflared", "restart")

    return app
