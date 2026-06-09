from __future__ import annotations

import os
import signal


def signal_name(signum: int | None) -> str | None:
    if signum is None:
        return None
    try:
        return signal.Signals(signum).name
    except Exception:
        return str(signum)


def exit_code_from_returncode(returncode: int | None) -> int | None:
    if returncode is None:
        return None
    if returncode < 0:
        return 128 + abs(returncode)
    return returncode


def forward_to_process_group(pgid: int | None, signum: int) -> None:
    if pgid is None:
        return
    try:
        os.killpg(pgid, signum)
    except ProcessLookupError:
        pass

