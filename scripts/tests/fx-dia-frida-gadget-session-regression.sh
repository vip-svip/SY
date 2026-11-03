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
    "Gadget attach action is reachable from UI": 'button("连接 Gadget、加载当前脚本并恢复 WAIT", () -> attachToGadgetAndResume())',
    "Gadget message/console log action is reachable from UI": 'button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog())',
    "Gadget session stop action is reachable from UI": 'button("停止 Gadget 会话", () -> stopGadgetSession())',
    "separate Frida CLI path helper": "currentFridaCliPath()",
    "attach validates CLI executable path": "if (!validPath(cli))",
    "target is revalidated as debuggable": "ApplicationInfo.FLAG_DEBUGGABLE",
    "system packages are excluded": "ApplicationInfo.FLAG_SYSTEM",
    "target process must be running": "FX_GADGET_TARGET_NOT_RUNNING",
    "process enumeration is scoped to target package": "index($2,pkg",
    "Frida script size is bounded": "sourceBytes.length > 48 * 1024",
    "Frida script rejects NUL": "source.indexOf(0) >= 0",
    "Gadget script uses random private temp": '.gadget-$port.XXXXXX',
    "Gadget script temp is private": "chmod 600",
    "Gadget log directory is private": "chmod 700",
    "Gadget log file is private": "chmod 600",
    "per-port start lock prevents duplicate sessions": ".gadget-$port.start-lock",
    "start lock is acquired atomically": 'mkdir \\"$start_lock\\"',
    "session script is passed to Frida CLI": '-n Gadget -l',
    "remote endpoint is loopback only": '127.0.0.1:$port',
    "persistent stdin FIFO exists": 'mkfifo -m 600',
    "stdin feeder has a port-specific identity": "fx-gadget-feed-$port",
    "CLI session survives Activity return": "nohup",
    "PID record is staged before rename": '.gadget-$port.pid.XXXXXX',
    "session log viewer is bounded": "tail -n 500",
    "Gadget WAIT/RESUME config semantics remain": 'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget rejects frida-server port": "if (port == 27042)",
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")
attach = source[source.index("private void attachToGadgetAndResume()"):
                 source.index("private void stopGadgetSession()")]
stop = source[source.index("private void stopGadgetSession()"):
               source.index("private void showGadgetSessionLog()")]
if "currentInjectorPath()" in attach or "String injector" in attach:
    raise SystemExit("FAIL: remote Gadget session must use frida CLI, not the frida-inject binary")
if "Runtime.exec" in attach:
    raise SystemExit("FAIL: Frida attach must not bypass the bounded RootAccess command bridge")
if "runRoot(command, 20000L" not in attach:
    raise SystemExit("FAIL: persistent Gadget command must use the bounded RootAccess worker")
if "nohup sh -c 'while kill -0 " not in attach or "fx-gadget-feed-$port" not in attach:
    raise SystemExit("FAIL: FIFO feeder must be the fixed CLI-PID-bound helper, not a user-controlled shell payload")
if 'kill "$cli_pid"' not in stop or 'kill "$feed_pid"' not in stop:
    raise SystemExit("FAIL: session stop must terminate both owned processes")
if "FX_GADGET_CLI_PID_CONFLICT" not in stop or "FX_GADGET_FEEDER_PID_CONFLICT" not in stop:
    raise SystemExit("FAIL: stop path must refuse unrelated PID owners")
print("PASS: Frida CLI Gadget session validates target/port, owns a persistent process, captures logs and provides a PID-checked stop action")
PY

# Exercise a long-lived remote Frida CLI session with a local mock. This validates
# FIFO lifetime, argument contract, PID ownership checks and cleanup; it does not
# claim Android-device Frida compatibility.
T=$(mktemp -d "/tmp/fx-dia-gadget-session.XXXXXX")
cleanup(){
  if [ -s "$T/logs/gadget-27043.pid" ]; then
    cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid")
    feed_pid=$(sed -n '2p' "$T/logs/gadget-27043.pid")
    kill "$cli_pid" "$feed_pid" 2>/dev/null || :
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -m 700 "$T/logs"
# The application requires a live target package. Make the mock package
# deterministic rather than depending on the GitHub runner's process names.
mkdir -p "$T/bin"
cat > "$T/bin/ps" <<'PS'
#!/bin/sh
printf '  PID NAME\n'
printf '12345 com.example.debuggable\n'
PS
chmod 700 "$T/bin/ps"
PATH="$T/bin:$PATH"
export PATH

cat > "$T/frida" <<'MOCK'
#!/bin/sh
set -eu
if [ "$1" = "--version" ]; then
  echo "Frida 17.0.0"
  exit 0
fi
[ "$1" = "-H" ] && [ "$2" = "127.0.0.1:27043" ]
[ "$3" = "-n" ] && [ "$4" = "Gadget" ]
[ "$5" = "-l" ]
[ -f "$6" ] && [ ! -L "$6" ]
[ "$(stat -c %a "$6")" = "600" ]
printf 'mock-send-message\nmock-console-log\n'
# Keep the CLI attached while the FIFO's feeder is alive.
cat >/dev/null
MOCK
chmod 700 "$T/frida"

cat > "$T/start.sh" <<'START'
#!/bin/sh
set -eu
cli=$1
pkg=$2
dir=$3
port=27043
log="$dir/gadget-$port.log"
script="$dir/gadget-$port.js"
pidfile="$dir/gadget-$port.pid"
pipe="$dir/gadget-$port.stdin"
lock="$dir/.gadget-$port.start-lock"
test -x "$cli" && test ! -L "$cli"
version=$("$cli" --version)
mkdir "$lock"
lock_held=1
tmp=
pid_tmp=
cleanup_start(){
  [ -z "$tmp" ] || rm -f "$tmp"
  [ -z "$pid_tmp" ] || rm -f "$pid_tmp"
  [ "$lock_held" != 1 ] || rmdir "$lock" 2>/dev/null || :
}
trap cleanup_start 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
tmp=$(mktemp "$dir/.gadget-$port.XXXXXX")
printf 'send("message"); console.log("console");\n' > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$script"
tmp=
: >> "$log"
chmod 600 "$log"
mkfifo -m 600 "$pipe"
nohup "$cli" -H "127.0.0.1:$port" -n Gadget -l "$script" < "$pipe" >> "$log" 2>&1 &
cli_pid=$!
nohup sh -c 'while kill -0 "$1" 2>/dev/null; do sleep 1; done' "fx-gadget-feed-$port" "$cli_pid" "$pipe" > "$pipe" 2>/dev/null < /dev/null &
feed_pid=$!
pid_tmp=$(mktemp "$dir/.gadget-$port.pid.XXXXXX")
printf '%s\n%s\n%s\n%s\n%s\n' "$cli_pid" "$feed_pid" "$cli" "$pkg" "$port" > "$pid_tmp"
chmod 600 "$pid_tmp"
mv -f "$pid_tmp" "$pidfile"
pid_tmp=
sleep 0.2
kill -0 "$cli_pid"
kill -0 "$feed_pid"
lock_held=0
rmdir "$lock"
echo "FX_GADGET_SESSION_STARTED|$cli_pid|$feed_pid|$version"
START
chmod 700 "$T/start.sh"

cat > "$T/stop.sh" <<'STOP'
#!/bin/sh
set -eu
dir=$1
port=27043
pidfile="$dir/gadget-$port.pid"
pipe="$dir/gadget-$port.stdin"
[ ! -L "$pidfile" ] && [ ! -L "$pipe" ]
[ -s "$pidfile" ] || { echo FX_GADGET_SESSION_NOT_RUNNING; exit 0; }
cli_pid=$(sed -n '1p' "$pidfile")
feed_pid=$(sed -n '2p' "$pidfile")
cli=$(sed -n '3p' "$pidfile")
case "$cli_pid:$feed_pid" in *[!0-9:]*|:*) exit 22;; esac
if kill -0 "$cli_pid" 2>/dev/null; then
  cmd=$(tr '\000' ' ' < /proc/"$cli_pid"/cmdline 2>/dev/null || :)
  case "$cmd" in *"$cli"*'127.0.0.1:27043'*Gadget*) kill "$cli_pid";;
    *) echo FX_GADGET_CLI_PID_CONFLICT; exit 23;;
  esac
fi
if kill -0 "$feed_pid" 2>/dev/null; then
  feed_cmd=$(tr '\000' ' ' < /proc/"$feed_pid"/cmdline 2>/dev/null || :)
  case "$feed_cmd" in *"fx-gadget-feed-27043"*"$pipe"*) kill "$feed_pid";;
    *) echo FX_GADGET_FEEDER_PID_CONFLICT; exit 24;;
  esac
fi
rm -f "$pidfile"
[ ! -L "$pipe" ] && rm -f "$pipe"
echo FX_GADGET_SESSION_STOPPED
STOP
chmod 700 "$T/stop.sh"

"$T/start.sh" "$T/frida" "com.example.debuggable" "$T/logs" > "$T/start.result"
grep -Fq "FX_GADGET_SESSION_STARTED" "$T/start.result"
sleep 0.2
grep -Fq "mock-send-message" "$T/logs/gadget-27043.log"
grep -Fq "mock-console-log" "$T/logs/gadget-27043.log"
[ -s "$T/logs/gadget-27043.pid" ] && [ -p "$T/logs/gadget-27043.stdin" ]
[ ! -d "$T/logs/.gadget-27043.start-lock" ]

"$T/stop.sh" "$T/logs" > "$T/stop.result"
grep -Fq FX_GADGET_SESSION_STOPPED "$T/stop.result"
[ ! -e "$T/logs/gadget-27043.pid" ] && [ ! -e "$T/logs/gadget-27043.stdin" ]
[ -z "$(find "$T/logs" -maxdepth 1 -name '.gadget-27043.*' -print -quit)" ] || {
  echo "FAIL: temporary Gadget session script/PID file leaked" >&2
  exit 1
}
echo "PASS: Frida CLI mock stays attached, records session output and stops only the recorded CLI/feeder processes"
