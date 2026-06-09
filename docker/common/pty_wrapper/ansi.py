from __future__ import annotations

import re

ANSI_RE = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def normalize_plain_text(raw: bytes | str) -> str:
    if isinstance(raw, bytes):
        text = raw.decode("utf-8", errors="replace")
    else:
        text = raw

    text = strip_ansi(text)
    out: list[str] = []
    current = ""
    index = 0
    while index < len(text):
        char = text[index]
        if char == "\r":
            if index + 1 < len(text) and text[index + 1] == "\n":
                out.append(current)
                current = ""
                index += 1
            else:
                current = ""
        elif char == "\n":
            out.append(current)
            current = ""
        else:
            current += char
        index += 1

    if current:
        out.append(current)

    suffix = "\n" if text.endswith(("\n", "\r")) else ""
    return "\n".join(out) + suffix
