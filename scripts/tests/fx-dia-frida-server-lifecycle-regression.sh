#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }

python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")

def body(signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start + len(signature))
    return source[start:end]

guards = body("private String serverProcessGuards()", "private void startServer()")
start = body("private void startServer()", "private void stopServer()")
stop = body("private void stopServer()", "private void chooseTarget()")
check = body("private void checkRuntime()", "private String serverProcessGuards()")

required_guards = {
    "PID liveness rejects zombies": "Z|X|x",
    "PID liveness checks the process": r'''kill -0 \"$fx_server_pid\"''',
    "executable path is matched exactly": r'''sed -n '1p')\" = \"$server\"''',
    "listen argument is matched exactly": r'''sed -n '2p')\" = \"-l\"''',
    "loopback endpoint is matched exactly": r'''sed -n '3p')\" = \"127.0.0.1:27042\"''',
    "full command line is read from proc": "/proc/$fx_server_pid/cmdline",
    "process start time comes from proc stat field 22": "awk '{print $20}'",
    "start time is exposed as a shared identity helper": "server_pid_starttime()",

}
for label, needle in required_guards.items():
    if needle not in guards:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

state_parent_guard = body("private String checkedDiaServerStateDirectoryPrefix()", "private String prepareDiaLogsDirectoryPrefix()")
for label, needle in (
    ("server state parent guard requires real /data and /data/adb directories", "for path in /data /data/adb; do"),
    ("server state parent guard rejects a symlinked state directory before creation", "[ ! -L '/data/adb/privacyguard' ]"),
    ("server state parent guard reports unsafe paths explicitly", "FX_FRIDA_UNSAFE_STATE_PARENT"),
):
    if needle not in state_parent_guard:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

required_start = {
    "server path must be executable and not symlinked": r'''test -x \"$server\" && test ! -L \"$server\"''',
    "startup invokes the parent-path guard before creating the state directory": "checkedDiaServerStateDirectoryPrefix()",
    "state, PID, lock and log paths reject symlinks": r'''[ ! -L \"$pidfile\" ] && [ ! -L \"$lock\" ] && [ ! -L \"$log\" ]''',
    "concurrent starts are serialized": r'''mkdir \"$lock\"''',
    "PID record uses a randomized same-directory temp": ".dia-frida-server.pid.XXXXXX",
    "PID record replacement is atomic": r'''mv -f \"$tmp\" \"$pidfile\"''',
    "PID record is private": r'''chmod 600 \"$tmp\"''',
    "server stays on loopback": "127.0.0.1:27042",
    "untracked matching server is not duplicated": "server=already-running-unmanaged",
    "startup verifies process identity": r'''server_pid_matches \"$pid\"''',
    "startup persists PID, executable, port and process starttime": r'''printf '%s\\n%s\\n%s\\n%s\\n' \"$pid\" \"$server\" 27042 \"$spawned_start\"''',
    "startup refuses old PID-only records while process remains live": "FX_FRIDA_PID_RECORD_LEGACY_UNVERIFIED",
    "startup checks current process starttime against its new record": r'''[ \"$current_start\" = \"$spawned_start\" ]''',
    "startup cleanup checks the original process starttime before TERM": r'''[ \"$(server_pid_starttime \"$spawned_pid\" 2>/dev/null || :)\" = \"$spawned_start\" ]''',

}
for label, needle in required_start.items():
    if needle not in start:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")
if "grep -Fq" in start or "pkill" in start or "killall" in start:
    raise SystemExit("FAIL: start path uses substring or broad process matching")
cleanup_pid_guard = r'''if [ -n \"$spawned_pid\" ] && [ -n \"$spawned_start\" '''
cleanup_start_guard = r'''&& [ \"$(server_pid_starttime \"$spawned_pid\" 2>/dev/null || :)\" = \"$spawned_start\" ] '''
cleanup_owner_guard = r'''&& server_pid_matches \"$spawned_pid\"; then kill -TERM \"$spawned_pid\"'''
for label, needle in (("cleanup PID/starttime guard", cleanup_pid_guard),
                      ("cleanup starttime recheck", cleanup_start_guard),
                      ("cleanup executable identity and TERM", cleanup_owner_guard)):
    if needle not in start:
        raise SystemExit(f"FAIL: startup cleanup may signal only an unchanged process: {label}")
if not (start.index(cleanup_pid_guard) < start.index(cleanup_start_guard) < start.index(cleanup_owner_guard)):
    raise SystemExit("FAIL: startup cleanup must verify PID starttime and executable before TERM")
    raise SystemExit("FAIL: startup cleanup must verify both original starttime and exact executable before TERM")

required_stop = {
    "stop validates the stored port": r'''[ \"$port\" = 27042 ]''',
    "stop invokes the parent-path guard before creating the state directory": "checkedDiaServerStateDirectoryPrefix()",
    "stop reads the persisted process starttime": "expected_start=$(sed -n '4p' \\\"$pidfile\\\")",
    "stop refuses old PID-only records": "FX_FRIDA_PID_RECORD_LEGACY_UNVERIFIED",
    "stop verifies starttime before TERM": r'''[ \"$actual_start\" = \"$expected_start\" ]''',
    "stop rechecks starttime during bounded wait": "actual_start=$(server_pid_starttime",
    "stop preserves record when PID is reused": "FX_FRIDA_PID_REUSED",

    "stop validates the stored executable path": "*[!A-Za-z0-9_./-]*|*..*",
    "stop verifies ownership before signal": r'''server_pid_matches \"$pid\" ||''',
    "stop sends TERM only": r'''kill -TERM \"$pid\"''',
    "stop uses a bounded wait": "FX_FRIDA_SERVER_STOP_TIMEOUT",
    "stop removes its record only after exit": r'''rm -f \"$pidfile\"''',
}
for label, needle in required_stop.items():
    if needle not in stop:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")
if "kill -KILL" in stop or "pkill" in stop or "killall" in stop:
    raise SystemExit("FAIL: stop must not force-kill or broadly match processes")
if stop.index("FX_FRIDA_SERVER_STOP_TIMEOUT") > stop.index(r'''rm -f \"$pidfile\"'''):
    raise SystemExit("FAIL: stop deletes PID record before timeout check")
if "server_pid_matches" not in check or "server_pid_starttime" not in check or "grep -Fq" in check:
    raise SystemExit("FAIL: runtime status must use exact process and start-time identity")
if "stored_start" not in check or "server=pid-reused" not in check:
    raise SystemExit("FAIL: runtime status must distinguish a reused PID from the recorded server")

print("PASS: Frida server lifecycle is serialized, atomic, loopback-only and exact-process-owned")
PY
