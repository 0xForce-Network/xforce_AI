from __future__ import annotations

import base64
import hashlib
import hmac
import os
import time
from dataclasses import dataclass
from typing import Any

import yaml


SECRET_KEYS = ("TOKEN", "PASSWORD", "SECRET", "KEY")


def mask_secret(value: str | None) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "***MASKED***"
    return f"{value[:3]}***{value[-3:]}"


def mask_mapping(data: dict[str, Any]) -> dict[str, Any]:
    masked: dict[str, Any] = {}
    for key, value in data.items():
        if any(marker in key.upper() for marker in SECRET_KEYS):
            masked[key] = mask_secret(str(value))
        else:
            masked[key] = value
    return masked


@dataclass(frozen=True)
class AuthConfig:
    token: str = ""
    cookie_name: str = "xforce_session"
    cookie_secret: str = ""
    bearer_enabled: bool = True
    header_name: str = "X-XForce-Token"
    query_name: str = "token"
    cookie_ttl_seconds: int = 86400

    @classmethod
    def from_yaml_env(cls, path: str | os.PathLike[str] | None = None) -> "AuthConfig":
        data: dict[str, Any] = {}
        if path and os.path.exists(path):
            loaded = yaml.safe_load(open(path, encoding="utf-8")) or {}
            if isinstance(loaded, dict):
                data = dict(loaded.get("auth") or {})
        token = os.environ.get("XFORCE_AUTH_TOKEN") or str(data.get("token") or "")
        cookie_name = os.environ.get("XFORCE_AUTH_COOKIE_NAME") or str(data.get("cookieName") or "xforce_session")
        cookie_secret = os.environ.get("XFORCE_AUTH_COOKIE_SECRET") or str(data.get("cookieSecret") or token or "")
        bearer_raw = os.environ.get("XFORCE_AUTH_BEARER_ENABLED", str(data.get("bearerEnabled", "1")))
        return cls(
            token=token,
            cookie_name=cookie_name,
            cookie_secret=cookie_secret,
            bearer_enabled=str(bearer_raw).lower() not in {"0", "false", "no", "off"},
            header_name=str(data.get("headerName") or "X-XForce-Token"),
            query_name=str(data.get("queryName") or "token"),
            cookie_ttl_seconds=int(data.get("cookieTtlSeconds") or 86400),
        )

    def masked(self) -> dict[str, Any]:
        return {
            "tokenConfigured": bool(self.token),
            "token": mask_secret(self.token),
            "cookieName": self.cookie_name,
            "cookieSecret": mask_secret(self.cookie_secret),
            "bearerEnabled": self.bearer_enabled,
            "headerName": self.header_name,
            "queryName": self.query_name,
            "cookieTtlSeconds": self.cookie_ttl_seconds,
        }


def sign_cookie(token: str, secret: str, now: int | None = None) -> str:
    issued = int(now or time.time())
    payload = f"v1:{issued}:{hashlib.sha256(token.encode()).hexdigest()}"
    signature = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    raw = f"{payload}:{signature}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def verify_cookie(cookie_value: str, token: str, secret: str, ttl_seconds: int = 86400, now: int | None = None) -> bool:
    if not cookie_value or not token or not secret:
        return False
    try:
        padded = cookie_value + "=" * (-len(cookie_value) % 4)
        raw = base64.urlsafe_b64decode(padded.encode()).decode()
        version, issued_text, token_hash, signature = raw.split(":", 3)
        if version != "v1":
            return False
        issued = int(issued_text)
    except Exception:  # noqa: BLE001
        return False
    if int(now or time.time()) - issued > ttl_seconds:
        return False
    expected_payload = f"v1:{issued}:{hashlib.sha256(token.encode()).hexdigest()}"
    expected_signature = hmac.new(secret.encode(), expected_payload.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(token_hash, hashlib.sha256(token.encode()).hexdigest()) and hmac.compare_digest(signature, expected_signature)


def token_matches(candidate: str | None, cfg: AuthConfig) -> bool:
    return bool(candidate and cfg.token and hmac.compare_digest(candidate, cfg.token))
