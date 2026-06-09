#!/usr/bin/env bash
set -Eeuo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wrap="/opt/xforce-ai/bin/xforce-pty-wrap"

cat > "$tmp/ansi.py" <<'EOF_ANSI'
import sys, time
sys.stdout.write("\x1b[31mRED\x1b[0m\n")
sys.stdout.write("progress 0%\r")
sys.stdout.flush()
time.sleep(0.1)
sys.stdout.write("progress 100%\n")
sys.stdout.flush()
print("tty=" + str(sys.stdout.isatty()))
EOF_ANSI

cat > "$tmp/trap_term.py" <<'EOF_TERM'
import signal, sys, time

def on_term(signum, frame):
    with open(sys.argv[1], "w", encoding="utf-8") as handle:
        handle.write("term\n")
    sys.exit(42)

signal.signal(signal.SIGTERM, on_term)
signal.signal(signal.SIGINT, on_term)
while True:
    time.sleep(0.2)
EOF_TERM

cat > "$tmp/ignore_term.py" <<'EOF_IGNORE'
import signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
signal.signal(signal.SIGINT, signal.SIG_IGN)
while True:
    time.sleep(0.2)
EOF_IGNORE

"$wrap" run --run-id ansi --log-dir "$tmp/logs" --state-dir "$tmp/state" -- python3 "$tmp/ansi.py"
grep -q 'RED' "$tmp/logs/ansi/stdout.plain.log"
grep -q 'progress 100%' "$tmp/logs/ansi/stdout.plain.log"
grep -q $'\x1b\[31m' "$tmp/logs/ansi/stdout.ansi.log"
grep -q '^XFORCE_PTY_STATUS=exited' "$tmp/logs/ansi/state.env"

"$wrap" run --run-id signal --log-dir "$tmp/logs" --state-dir "$tmp/state" -- python3 "$tmp/trap_term.py" "$tmp/term.flag" &
wrap_pid=$!
sleep 1
kill -TERM "$wrap_pid"
signal_rc=0
wait "$wrap_pid" || signal_rc=$?
[ "$signal_rc" = "42" ]
[ -f "$tmp/term.flag" ]
grep -q '^XFORCE_PTY_EXIT_CODE=42' "$tmp/logs/signal/state.env"

"$wrap" run --run-id timeout --log-dir "$tmp/logs" --state-dir "$tmp/state" --terminate-timeout 1 --kill-timeout 1 -- python3 "$tmp/ignore_term.py" &
wrap_pid=$!
sleep 1
kill -TERM "$wrap_pid"
wait "$wrap_pid" || true
grep -q '^XFORCE_PTY_STATUS=timeout' "$tmp/logs/timeout/state.env"

"$wrap" run --run-id tty --log-dir "$tmp/logs" --state-dir "$tmp/state" -- python3 -c 'import sys; print(sys.stdout.isatty())'
grep -q '^True$' "$tmp/logs/tty/stdout.plain.log"

echo "xforce_AI PTY wrapper smoke test passed"
