from __future__ import annotations

import errno
import fcntl
import os
import selectors
import shlex
import signal
import struct
import subprocess
import termios
from dataclasses import dataclass
from pathlib import Path

from .ansi import normalize_plain_text
from .signals import exit_code_from_returncode, forward_to_process_group, signal_name
from .state import WrapperContext, WrapperState, utc_now, write_state_files


@dataclass
class RunnerResult:
    state: WrapperState
    returncode: int


def _set_winsize(fd: int, rows: int, cols: int) -> None:
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def _ensure_text(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def run_command(ctx: WrapperContext, command: list[str]) -> RunnerResult:
    ctx.resolve()
    ctx.run_dir.mkdir(parents=True, exist_ok=True)
    ctx.state_dir.mkdir(parents=True, exist_ok=True)

    ansi_log = ctx.ansi_log.open("ab", buffering=0)
    plain_log = ctx.plain_log.open("w", encoding="utf-8")
    plain_raw = bytearray()

    state = WrapperState(
        run_id=ctx.run_id,
        command=command,
        started_at=utc_now(),
        ansi_log=str(ctx.ansi_log),
        plain_log=str(ctx.plain_log),
        cwd=str(ctx.cwd or Path.cwd()),
    )
    write_state_files(ctx, state)

    master_fd, slave_fd = os.openpty()
    _set_winsize(slave_fd, ctx.rows, ctx.cols)

    child_env = os.environ.copy()
    child_env.update(ctx.env_overrides)
    child_env["TERM"] = ctx.term
    child_env["COLUMNS"] = str(ctx.cols)
    child_env["LINES"] = str(ctx.rows)

    proc = subprocess.Popen(
        command,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        cwd=str(ctx.cwd) if ctx.cwd else None,
        env=child_env,
        start_new_session=True,
        close_fds=True,
    )
    os.close(slave_fd)
    state.pid = proc.pid
    state.pgid = proc.pid
    state.status = "running"
    write_state_files(ctx, state)

    os.set_blocking(master_fd, False)
    selector = selectors.DefaultSelector()
    selector.register(master_fd, selectors.EVENT_READ)

    terminate_deadline: float | None = None
    kill_deadline: float | None = None
    received_signal: int | None = None
    eof = False

    def _handle_signal(signum: int, _frame) -> None:  # type: ignore[no-untyped-def]
        nonlocal received_signal, terminate_deadline
        received_signal = signum
        forward_to_process_group(state.pgid, signum)
        if signum in {signal.SIGTERM, signal.SIGINT, signal.SIGHUP}:
            terminate_deadline = os.times().elapsed + ctx.terminate_timeout
        if signum == signal.SIGWINCH:
            try:
                _set_winsize(master_fd, ctx.rows, ctx.cols)
            except Exception:
                pass

    previous_handlers = {}
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP, signal.SIGWINCH):
        try:
            previous_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, _handle_signal)
        except Exception:
            continue

    try:
        while True:
            events = selector.select(timeout=0.1)
            for key, _mask in events:
                if key.fileobj != master_fd:
                    continue
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        eof = True
                        chunk = b""
                    else:
                        raise
                if chunk:
                    ansi_log.write(chunk)
                    ansi_log.flush()
                    plain_raw.extend(chunk)
                    plain_text = normalize_plain_text(bytes(plain_raw))
                    plain_log.seek(0)
                    plain_log.truncate(0)
                    plain_log.write(plain_text)
                    plain_log.flush()
                    if ctx.forward_console:
                        os.write(1, chunk)
                else:
                    eof = True

            returncode = proc.poll()
            now = os.times().elapsed
            if terminate_deadline is not None and returncode is None and now >= terminate_deadline:
                forward_to_process_group(state.pgid, signal.SIGKILL)
                kill_deadline = now + ctx.kill_timeout
                terminate_deadline = None
                state.status = "timeout"
                write_state_files(ctx, state)

            if kill_deadline is not None and returncode is None and now >= kill_deadline:
                forward_to_process_group(state.pgid, signal.SIGKILL)
                kill_deadline = None

            if eof and returncode is not None:
                break

        returncode = proc.wait()
    finally:
        for sig, handler in previous_handlers.items():
            try:
                signal.signal(sig, handler)
            except Exception:
                pass
        selector.close()
        try:
            os.close(master_fd)
        except OSError:
            pass
        ansi_log.close()
        plain_log.close()

    state.ended_at = utc_now()
    state.exit_code = exit_code_from_returncode(returncode)
    if state.status == "timeout":
        state.signal = abs(returncode) if returncode < 0 else state.signal
    elif returncode < 0:
        state.signal = abs(returncode)
        state.status = "signaled"
    else:
        state.status = "exited"
    if received_signal is not None and state.signal is None and returncode >= 0:
        state.signal = received_signal
    write_state_files(ctx, state)
    return RunnerResult(state=state, returncode=state.exit_code or 0)
