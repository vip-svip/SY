#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }

python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = {
    "Frida CLI path is a distinct field":
        "private EditText fridaCliPath;",
    "Frida CLI path is read separately":
        "private String currentFridaCliPath()",
    "Frida CLI path persists in preferences":
        '"frida_cli_path"',
    "Frida CLI path restores after Activity recreation":
        'state.getString("fx_frida_cli_path"',
    "Frida CLI path is included in saved state":
        'outState.putString("fx_frida_cli_path"',
    "Frida CLI is checked before use":
        'cli_version=$(\\\"$cli\\\" --version 2>&1)',
    "Gadget attach action is reachable from the UI":
        'button("连接 Gadget、加载当前脚本并恢复 WAIT", () -> attachToGadgetAndResume())',
    "Gadget message/console log action is reachable from the UI":
        'button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog())',
    "Gadget stop action is reachable from the UI":
        'button("停止 Gadget 会话", () -> stopGadgetSession())',
    "Gadget remote endpoint is loopback-only":
        '127.0.0.1:$port',
    "Frida CLI attaches to the Gadget process and loads the script":
        '-n Gadget -l',
    "Frida CLI is run as a persistent background process":
        'nohup \\\\"$cli\\\\" -H',
    "stdin FIFO keeps the interactive CLI open":
        'nohup tail -f /dev/null',
    "one session lock prevents duplicate starts":
        'mkdir \\\\"$start_lock\\\\"',
    "session PID file uses a random same-directory temp":
        'pid_tmp=$(mktemp',
    "session PID file is atomically replaced":
        'mv -f \\\\"$pid_tmp\\\\" \\\\"$pidfile\\\\"',
    "session script temp uses a random same-directory name":
        '.gadget-$port.XXXXXX',
    "script and FIFO are private":
        'mkfifo -m 600',
    "private directory permissions are restricted":
        'chmod 700',
    "script and logs use owner-only access":
        'chmod 600',
    "script bytes are bounded":
        'sourceBytes.length > 48 * 1024',
    "script rejects NUL":
        'source.indexOf(0) >= 0',
    "target is revalidated as debuggable":
        'targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE',
    "system apps are excluded":
        'targetInfo.flags & ApplicationInfo.FLAG_SYSTEM',
    "target package process must be active":
        'FX_GADGET_TARGET_NOT_RUNNING',
    "messages and console output are captured":
        '>> \\\\"$log\\\\" 2>&1',
    "Gadget log reader is bounded":
        'tail -n 500',
    "stop verifies process command line before killing":
        'FX_GADGET_CLI_PID_CONFLICT',
    "stop verifies feeder ownership before killing":
        'FX_GADGET_FEEDER_PID_CONFLICT',
    "WAIT/RESUME configuration remains available":
        'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget port stays separate from frida-server":
        'if (port == 27042)',
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

attach_start = source.index("private void attachToGadgetAndResume()")
attach_end = source.index("private void stopGadgetSession()", attach_start)
attach = source[attach_start:attach_end]
if 'currentInjectorPath()' in attach or ' -H "127.0.0.1:' not in attach:
    raise SystemExit("FAIL: remote Gadget connection must use the separate Frida CLI, not frida-inject")
if "0.0.0.0" in attach:
    raise SystemExit("FAIL: remote Gadget session must not use an all-interface endpoint")
stop_start = source.index("private void stopGadgetSession()")
stop_end = source.index("private void showGadgetSessionLog()", stop_start)
stop = source[stop_start:stop_end]
if "FLAG_DEBUGGABLE" in stop:
    raise SystemExit("FAIL: stop routine must use recorded process ownership, not a package-name guess")
print("PASS: Dia Gadget uses a separate persistent frida CLI session, private FIFO/script/PID files, ownership-checked stop and bounded logs")
PY

# Local mock of the remote Frida CLI contract and the persistent FIFO session.
# This validates argument order, script path, logs and ownership cleanup only;
# it does not claim device-side Frida/Gadget compatibility.
T=$(mktemp -d "/tmp/fx-dia-gadget-session.XXXXXX")
cleanup(){
  if [ -s "$T/session.pid" ]; then
    cli_pid=$(sed -n '1p' "$T/session.pid" 2>/dev/null || :)
    feed_pid=$(sed -n '2p' "$T/session.pid" 2>/dev/null || :)
    case "$cli_pid" in ''|*[!0-9]*) ;; *) kill "$cli_pid" 2>/dev/null || :;; esac
    case "$feed_pid" in ''|*[!0-9]*) ;; *) kill "$feed_pid" 2>/dev/null || :;; esac
  fi
  rm -rf "$T"
}
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
printf 'mock-session-ready\n'
cat "$6"
while IFS= read -r line; do
  :
done
MOCK
chmod 700 "$T/frida"
cat > "$T/start-session.sh" <<'RUN'
#!/bin/sh
set -eu
umask 077
cli=$1
dir=$2
port=27043
script="$dir/gadget-$port.js"
log="$dir/gadget-$port.log"
pidfile="$dir/gadget-$port.pid"
pipe="$dir/gadget-$port.stdin"
lock="$dir/.gadget-$port.start-lock"
mkdir "$lock"
lock_held=1
tmp=
pid_tmp=
cleanup_start(){
  [ -z "$tmp" ] || rm -f "$tmp"
  [ -z "$pid_tmp" ] || rm -f "$pid_tmp"
  [ "$lock_held" != 1 ] || rmdir "$lock" 2>/dev/null || :
}
trap cleanup_start EXIT HUP INT TERM
tmp=$(mktemp "$dir/.gadget-$port.XXXXXX")
printf 'send("mock-message"); console.log("mock-console");\n' > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$script"
tmp=
: >> "$log"
chmod 600 "$log"
mkfifo -m 600 "$pipe"
nohup "$cli" -H "127.0.0.1:$port" -n Gadget -l "$script" < "$pipe" >> "$log" 2>&1 &
cli_pid=$!
nohup tail -f /dev/null > "$pipe" 2>/dev/null < /dev/null &
feed_pid=$!
pid_tmp=$(mktemp "$dir/.gadget-$port.pid.XXXXXX")
printf '%s\n%s\n%s\n' "$cli_pid" "$feed_pid" "$cli" > "$pid_tmp"
chmod 600 "$pid_tmp"
mv -f "$pid_tmp" "$pidfile"
pid_tmp=
sleep 1
kill -0 "$cli_pid"
kill -0 "$feed_pid"
lock_held=0
rmdir "$lock"
echo "started=$cli_pid,$feed_pid"
RUN
chmod 700 "$T/start-session.sh"
"$T/start-session.sh" "$T/frida" "$T/logs" > "$T/status"
grep -Fq "started=" "$T/status"
grep -Fq "mock-session-ready" "$T/logs/gadget-27043.log"
grep -Fq 'send("mock-message")' "$T/logs/gadget-27043.log"
grep -Fq 'console.log("mock-console")' "$T/logs/gadget-27043.log"
[ "$(stat -c %a "$T/logs/gadget-27043.js")" = "600" ]
[ "$(stat -c %a "$T/logs/gadget-27043.pid")" = "600" ]
[ -p "$T/logs/gadget-27043.stdin" ]
cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid")
feed_pid=$(sed -n '2p' "$T/logs/gadget-27043.pid")
[ -d "/proc/$cli_pid" ] && [ -d "/proc/$feed_pid" ]
kill "$cli_pid"
kill "$feed_pid"
sleep 1
rm -f "$T/logs/gadget-27043.pid" "$T/logs/gadget-27043.stdin"
[ ! -e "$T/logs/gadget-27043.pid" ] && [ ! -e "$T/logs/gadget-27043.stdin" ]
[ -s "$T/logs/gadget-27043.log" ]
echo "PASS: Frida CLI Gadget mock attaches by -H/-n/-l, keeps FIFO session alive, captures output and cleans up"
