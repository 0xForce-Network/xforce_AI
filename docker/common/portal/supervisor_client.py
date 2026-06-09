from __future__ import annotations

import socket
import xmlrpc.client
from http.client import HTTPConnection, HTTPResponse
from pathlib import Path
from typing import Any


class UnixSocketHTTPConnection(HTTPConnection):
    def __init__(self, unix_socket: Path) -> None:
        super().__init__("localhost")
        self.unix_socket = unix_socket

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(str(self.unix_socket))


class UnixSocketTransport(xmlrpc.client.Transport):
    def __init__(self, unix_socket: Path) -> None:
        super().__init__()
        self.unix_socket = unix_socket

    def make_connection(self, host: str) -> UnixSocketHTTPConnection:
        return UnixSocketHTTPConnection(self.unix_socket)


class SupervisorClient:
    def __init__(self, socket_path: Path) -> None:
        self.socket_path = socket_path

    @property
    def available(self) -> bool:
        return self.socket_path.exists()

    def _proxy(self) -> xmlrpc.client.ServerProxy:
        transport = UnixSocketTransport(self.socket_path)
        return xmlrpc.client.ServerProxy("http://localhost/RPC2", transport=transport, allow_none=True)

    def ping(self) -> bool:
        if not self.available:
            return False
        try:
            self._proxy().supervisor.getState()
            return True
        except Exception:  # noqa: BLE001
            return False

    def get_all_process_info(self) -> list[dict[str, Any]]:
        return [dict(item) for item in self._proxy().supervisor.getAllProcessInfo()]

    def get_process_info(self, name: str) -> dict[str, Any]:
        return dict(self._proxy().supervisor.getProcessInfo(name))

    def start(self, name: str) -> None:
        self._proxy().supervisor.startProcess(name, True)

    def stop(self, name: str) -> None:
        self._proxy().supervisor.stopProcess(name, True)


__all__ = ["HTTPResponse", "SupervisorClient"]
