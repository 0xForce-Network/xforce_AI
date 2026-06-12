from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


class FileBrowserError(Exception):
    def __init__(self, status_code: int, error: str, message: str) -> None:
        self.status_code = status_code
        self.error = error
        self.message = message


@dataclass(frozen=True)
class FileRoot:
    name: str
    path: Path


def parse_file_roots(raw: str) -> dict[str, FileRoot]:
    roots: dict[str, FileRoot] = {}
    for item in raw.split(","):
        item = item.strip()
        if not item or ":" not in item:
            continue
        name, path = item.split(":", 1)
        name = name.strip().lower()
        if not name.replace("-", "").replace("_", "").isalnum():
            continue
        root_path = Path(path.strip()).resolve()
        root_path.mkdir(parents=True, exist_ok=True)
        roots[name] = FileRoot(name=name, path=root_path)
    return roots


def safe_child(root: FileRoot, rel_path: str) -> Path:
    rel_path = rel_path.strip().lstrip("/")
    candidate = (root.path / rel_path).resolve()
    if candidate != root.path and root.path not in candidate.parents:
        raise FileBrowserError(403, "path_denied", "requested path escapes the configured file root")
    return candidate


def file_entry(path: Path, root: FileRoot, ipfs: dict[str, Any] | None = None) -> dict[str, Any]:
    stat = path.stat()
    rel = "" if path == root.path else path.relative_to(root.path).as_posix()
    entry = {
        "name": path.name or root.name,
        "root": root.name,
        "path": rel,
        "type": "directory" if path.is_dir() else "file",
        "size": stat.st_size,
        "modified": stat.st_mtime,
    }
    if ipfs is not None and path.is_file():
        entry["ipfs"] = ipfs
    return entry


def list_dir_page(path: Path, root: FileRoot, *, page: int = 1, page_size: int = 15, search: str = "", sort: str = "name", order: str = "asc", ipfs_lookup: Any = None) -> dict[str, Any]:
    if not path.exists():
        raise FileBrowserError(404, "not_found", "path does not exist")
    if not path.is_dir():
        ipfs = ipfs_lookup(root, path, auto=True) if ipfs_lookup else None
        return {"root": root.name, "entry": file_entry(path, root, ipfs), "entries": []}
    normalized_search = search.strip().lower()
    entries = []
    for child in path.iterdir():
        ipfs = ipfs_lookup(root, child, auto=True) if ipfs_lookup and child.is_file() else None
        entries.append(file_entry(child, root, ipfs))
    if normalized_search:
        entries = [entry for entry in entries if normalized_search in entry["name"].lower() or normalized_search in entry["path"].lower()]
    sort_key = sort if sort in {"name", "type", "size", "modified"} else "name"
    reverse = order.lower() == "desc"
    entries = sorted(
        entries,
        key=lambda item: (
            item["type"] != "directory",
            item[sort_key].lower() if isinstance(item[sort_key], str) else item[sort_key],
            item["name"].lower(),
        ),
        reverse=reverse,
    )
    safe_page_size = min(max(page_size, 1), 100)
    safe_page = max(page, 1)
    total = len(entries)
    start = (safe_page - 1) * safe_page_size
    end = start + safe_page_size
    return {
        "root": root.name,
        "entry": file_entry(path, root),
        "entries": entries[start:end],
        "pagination": {"page": safe_page, "pageSize": safe_page_size, "total": total, "pages": max((total + safe_page_size - 1) // safe_page_size, 1)},
        "query": {"search": search, "sort": sort_key, "order": "desc" if reverse else "asc"},
    }
