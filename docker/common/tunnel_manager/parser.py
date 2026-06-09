from __future__ import annotations

import re

QUICK_URL_RE = re.compile(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com")


def parse_quick_url(text: str) -> str | None:
    match = QUICK_URL_RE.search(text)
    return match.group(0) if match else None
