#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }

python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
attach_start = source.index("private void attachToGadgetAndResume()")
attach_end = source.index("private void stopGadgetSession()", attach_start)
attach = source[attach_start:attach_end]
stop_start = attach_end
stop_end = source.index("private void showGadgetSessionLog()", stop_start)
stop = source[stop_start:stop_end]

required = {
    "Gadget attach action is reachable from the UI":
        'button("连接 Gadget、加载当前脚本并恢复 WAIT", () -> attachToGadgetAndResume())',
    "Gadget message/console log action is reachable from the UI":
        'button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog())',
    "persistent session uses the installed Frida CLI":
        "String cli = currentFridaCliPath();",
    "Frida CLI must be executable and not a symlink":
        "test -x",
    "Frida CLI version is checked before session start":
        "cli_version=",
    "Gadget control endpoint is loopback-only":
        '127.0.0.1:$port',
    "Frida CLI attaches to Gadget by name and loads the script":
        "-n Gadget -l",
    "remote endpoint uses selected Gadget port":
        '-H',
    "target is revalidated as debuggable before remote control":
        'targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE',
    "system packages are excluded":
        'targetInfo.flags & ApplicationInfo.FLAG_SYSTEM',
    "target process must currently be running":
        'FX_GADGET_TARGET_NOT_RUNNING',
    "target process enumeration matches target package":
        'index($2,pkg',
    "Frida script size is bounded":
        'sourceBytes.length > 48 * 1024',
    "Frida script rejects NUL":
        'source.indexOf(0) >= 0',
    "script is staged using unpredictable same-directory temp":
        '.gadget-$port.XXXXXX',
    "persistent input FIFO is created with private permissions":
        'mkfifo -m 600',
    "persistent input feeder remains attached to the FIFO":
        'tail -f /dev/null >',
    "session PID record stores CLI and feeder":
        'cli_pid',
    "CLI output is captured in the per-port log":
        '2>&1',
    "session start has an explicit live marker":
        'FX_GADGET_SESSION_STARTED',
    "already-running session is not duplicated":
        'FX_GADGET_SESSION_ALREADY_RUNNING',
    "session stop validates the recorded CLI process":
        'FX_GADGET_CLI_PID_CONFLICT',
    "session stop validates the feeder process":
        'FX_GADGET_FEEDER_PID_CONFLICT',
    "log viewer only reads bounded tail":
        'tail -n 500',
    "Gadget config preserves WAIT/RESUME semantics":
        'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget config rejects frida-server port":
        'if (port == 27042)',
}
for label, needle in required.items():
    target = stop if "session stop" in label else (attach if label.startswith(("persistent", "Frida CLI", "Gadget control", "Frida CLI attaches", "remote endpoint", "target ", "system ", "target process", "Frida script", "persistent input", "session PID", "CLI output", "session start", "already-running")) else source)
    if needle not in target:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

if "currentInjectorPath()" in attach or "frida-inject" in attach:
    raise SystemExit("FAIL: persistent Gadget session must use frida CLI, not one-shot frida-inject")
if "0.0.0.0" in attach:
    raise SystemExit("FAIL: remote Gadget attach must not bind to all interfaces")
if "Runtime.exec" in attach or "sh -c" in attach:
    raise SystemExit("FAIL: Frida attach must use the bounded RootAccess command bridge")
if "FLAG_DEBUGGABLE" not in attach or "FLAG_SYSTEM" not in attach:
    raise SystemExit("FAIL: target eligibility checks were removed from the attach action")
print("PASS: Frida Gadget session uses persistent CLI, validated loopback endpoint, target checks, private FIFO/PID state and bounded logs")
PY

# Exercise a persistent Frida CLI session contract with a local mock. This guards
# command arguments, script privacy, FIFO lifetime, PID ownership and clean stop;
# it does not claim that an actual Android Gadget has been installed or attached.
T=$(mktemp -d "/tmp/fx-dia-gadget-session.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
mkdir -m 700 "$T/logs"

cat > "$T/frida" <<'MOCK'
#!/bin/sh
set -eu
[ "$1" = "-H" ]
[ "$2" = "127.0.0.1:27043" ]
[ "$3" = "-n" ]
[ "$4" = "Gadget" ]
[ "$5" = "-l" ]
[ -f "$6" ] && [ ! -L "$6" ]
[ "$(stat -c %a "$6")" = "600" ]
printf '%s\n' "$@" > "$MOCK_ARGS"
printf 'mock-cli-started\n'
while IFS= read -r line; do
  [ -n "$line" ] && printf 'mock-stdin:%s\n' "$line"
done
MOCK
chmod 700 "$T/frida"

cat > "$T/start-session.sh" <<'START'
#!/bin/sh
set -eu
umask 077
cli=$1
pkg=$2
log=$3
script=$4
pidfile=$5
pipe=$6
test -x "$cli" && test ! -L "$cli"
cli_version=$("$cli" --version 2>&1) || exit 20
pids=$(ps -A -o PID,NAME 2>/dev/null | awk -v pkg="$pkg" 'NR>1 && $1 ~ /^[0-9]+$/ && ($2==pkg || index($2,pkg ":")==1) {print $1}')
[ -n "$pids" ]
dir=$(dirname "$log")
test -d "$dir" && test ! -L "$dir"
[ ! -L "$log" ] && [ ! -L "$pidfile" ] && [ ! -L "$pipe" ] && [ ! -L "$script" ]
tmp=$(mktemp "$dir/.gadget-27043.XXXXXX")
[ -f "$tmp" ] && [ ! -L "$tmp" ]
cleanup_tmp(){ [ -z "$tmp" ] || rm -f "$tmp"; }
trap cleanup_tmp 0
printf 'send("hello"); console.log("console");\n' > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$script"
tmp=
chmod 600 "$script"
: >> "$log"
chmod 600 "$log"
rm -f "$pipe"
mkfifo -m 600 "$pipe"
"$cli" -H "127.0.0.1:27043" -n Gadget -l "$script" < "$pipe" >> "$log" 2>&1 & cli_pid=$!
tail -f /dev/null > "$pipe" 2>/dev/null < /dev/null & feed_pid=$!
printf '%s\n%s\n%s\n%s\n%s\n' "$cli_pid" "$feed_pid" "$cli" "$pkg" "27043" > "$pidfile"
chmod 600 "$pidfile"
sleep 0.2
kill -0 "$cli_pid"
kill -0 "$feed_pid"
printf 'FX_GADGET_SESSION_STARTED\ncli_pid=%s\nfeeder_pid=%s\ncli_version=%s\n' "$cli_pid" "$feed_pid" "$cli_version"
START
chmod 700 "$T/start-session.sh"

export MOCK_ARGS="$T/mock-args"
SESSION_LOG="$T/logs/gadget-27043.log"
SESSION_SCRIPT="$T/logs/gadget-27043.js"
SESSION_PID="$T/logs/gadget-27043.pid"
SESSION_PIPE="$T/logs/gadget-27043.stdin"
"$T/start-session.sh" "$T/frida" com.example.debuggable "$SESSION_LOG" "$SESSION_SCRIPT" "$SESSION_PID" "$SESSION_PIPE" > "$T/status"

grep -Fq FX_GADGET_SESSION_STARTED "$T/status"
grep -Fqx -- "-H" "$MOCK_ARGS"
grep -Fqx -- "127.0.0.1:27043" "$MOCK_ARGS"
grep -Fqx -- "-n" "$MOCK_ARGS"
grep -Fqx -- "Gadget" "$MOCK_ARGS"
grep -Fqx -- "-l" "$MOCK_ARGS"
grep -Fqx -- "$SESSION_SCRIPT" "$MOCK_ARGS"
[ "$(stat -c %a "$SESSION_SCRIPT")" = "600" ]
[ "$(stat -c %a "$SESSION_LOG")" = "600" ]
[ "$(stat -c %a "$SESSION_PID")" = "600" ]
[ "$(stat -c %a "$SESSION_PIPE")" = "600" ]
[ "$(wc -l < "$SESSION_PID")" -eq 5 ]
cli_pid=$(sed -n '1p' "$SESSION_PID")
feed_pid=$(sed -n '2p' "$SESSION_PID")
[ -n "$cli_pid" ] && [ -n "$feed_pid" ]
kill -0 "$cli_pid"
kill -0 "$feed_pid"

# Exercise the same ownership checks as stopGadgetSession before signalling.
cli_cmd=$(tr '\000' ' ' < "/proc/$cli_pid/cmdline" 2>/dev/null || :)
case "$cli_cmd" in *"$T/frida"*'127.0.0.1:27043'*Gadget*) ;; *) echo "FAIL: CLI PID record does not identify the Gadget session" >&2; exit 1 ;; esac
feed_cmd=$(tr '\000' ' ' < "/proc/$feed_pid/cmdline" 2>/dev/null || :)
case "$feed_cmd" in *tail*'/dev/null'*) ;; *) echo "FAIL: feeder PID record does not identify the private FIFO feeder" >&2; exit 1 ;; esac
kill "$cli_pid" "$feed_pid" 2>/dev/null || :
sleep 0.2
rm -f "$SESSION_PID" "$SESSION_PIPE"
[ ! -e "$SESSION_PID" ] && [ ! -e "$SESSION_PIPE" ]
[ -z "$(find "$T/logs" -maxdepth 1 -name '.gadget-27043.*' -print -quit)" ] || {
  echo "FAIL: temporary Gadget script leaked after session start" >&2
  exit 1
}
grep -Fq mock-cli-started "$SESSION_LOG"
echo "PASS: persistent Gadget CLI session preserves loopback endpoint, PID ownership, FIFO lifecycle and output log"
