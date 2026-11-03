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
    "Gadget target process validator is called": "validateProcessName(targetPackage, process)",
    "target UID is captured from PackageManager": "targetUid = targetInfo.uid",
    "process enumeration matches one exact target process": "$2==proc",
    "process enumeration verifies target app UID": '\\\"$uid\\\" = \\\"$target_uid\\\"',
    "process UID comes from proc status": '"/$pid/status"',
    "Frida script size is bounded": "sourceBytes.length > 48 * 1024",
    "Frida script rejects NUL": "source.indexOf(0) >= 0",
    "Gadget script uses random private temp": '.gadget-$port.XXXXXX',
    "Gadget script temp is private": "chmod 600",
    "Gadget log directory is private": "chmod 700",
    "Gadget log file is private": "chmod 600",
    "per-port start lock prevents duplicate sessions": ".gadget-$port.start-lock",
    "existing session record binds target package": "old_pkg=$(sed -n '4p' \\\"$pidfile\\\")",
    "existing session record binds TCP port": "old_port=$(sed -n '5p' \\\"$pidfile\\\")",
    "existing session record binds exact process": "old_process=$(sed -n '6p' \\\"$pidfile\\\")",
    "stop record binds exact process": "stored_process=$(sed -n '6p' \\\"$pidfile\\\")",
    "Gadget CLI start persists exact process identity": 'process=" + quote(processName)',

    "reattach refuses a different target": "FX_GADGET_SESSION_TARGET_CONFLICT",
    "stop record validates package": "stored_pkg=$(sed -n '4p' \\\"$pidfile\\\")",
    "stop record validates port": "stored_port=$(sed -n '5p' \\\"$pidfile\\\")",
    "start lock is acquired atomically": 'mkdir \\"$start_lock\\"',
    "stop acquires the same per-port lock": 'start_lock=" + quote(startLockPath)',
    "stop refuses an active Gadget lifecycle operation": "FX_GADGET_START_IN_PROGRESS",
    "stop releases only its own lock": "cleanup_stop()",
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
for process_id in ("cli_pid", "feed_pid"):
    escaped_kill = 'kill \\"$' + process_id + '\\"'
    if escaped_kill not in stop:
        raise SystemExit(f"FAIL: session stop must terminate the owned {process_id} process")
if "FX_GADGET_CLI_PID_CONFLICT" not in stop or "FX_GADGET_FEEDER_PID_CONFLICT" not in stop:
    raise SystemExit("FAIL: stop path must refuse unrelated PID owners")
if "final String expectedCli = currentFridaCliPath();" not in stop:
    raise SystemExit("FAIL: stop path must bind to the currently configured Frida CLI")
if 'start_lock=" + quote(startLockPath)' not in stop or "trap cleanup_stop 0" not in stop:
    raise SystemExit("FAIL: stop path must hold the same per-port lock as attach")
if '[ \\"$cli\\" = \\"$expected_cli\\" ]' not in stop:
    raise SystemExit("FAIL: stop path must compare the recorded CLI path, not the Gadget JS path")
print("PASS: Frida CLI Gadget session validates target/port/CLI identity, owns a persistent process, captures logs and provides a PID-checked stop action")
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
printf '12346 com.example.debuggable:remote\n'
printf '12347 com.example.debuggable:spoof\n'
PS
chmod 700 "$T/bin/ps"
mkdir -p "$T/proc/12345" "$T/proc/12346" "$T/proc/12347"
printf 'Name: com.example.debuggable\nUid: 10002 10002 10002 10002\n' > "$T/proc/12345/status"
printf 'Name: com.example.debuggable:remote\nUid: 10002 10002 10002 10002\n' > "$T/proc/12346/status"
# Same process name shape, but a different app UID; name-only matching would accept it.
printf 'Name: com.example.debuggable:spoof\nUid: 10099 10099 10099 10099\n' > "$T/proc/12347/status"
export FX_GADGET_TEST_PROC_ROOT="$T/proc"
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
proc=$4
port=27043
log="$dir/gadget-$port.log"
script="$dir/gadget-$port.js"
pidfile="$dir/gadget-$port.pid"
pipe="$dir/gadget-$port.stdin"
lock="$dir/.gadget-$port.start-lock"
test -x "$cli" && test ! -L "$cli"
version=$("$cli" --version)
target_uid=10002
proc_root="$FX_GADGET_TEST_PROC_ROOT"
pids=$(ps -A -o PID,NAME 2>/dev/null | awk -v proc="$proc" 'NR>1 && $1 ~ /^[0-9]+$/ && $2==proc {print $1}' | while IFS= read -r pid; do
  uid=$(awk '$1=="Uid:" {print $2; exit}' "$proc_root/$pid/status" 2>/dev/null || :)
  [ "$uid" = "$target_uid" ] && printf '%s\n' "$pid" || :
done)
[ -n "$pids" ] || { echo FX_GADGET_TARGET_PROCESS_NOT_RUNNING; exit 4; }
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
if [ -s "$pidfile" ]; then
  old_cli=$(sed -n '1p' "$pidfile")
  old_feed=$(sed -n '2p' "$pidfile")
  old_cli_path=$(sed -n '3p' "$pidfile")
  old_pkg=$(sed -n '4p' "$pidfile")
  old_port=$(sed -n '5p' "$pidfile")
  old_process=$(sed -n '6p' "$pidfile")
  case "$old_cli:$old_feed" in *[!0-9:]*|:*) exit 22;; esac
  case "$old_port" in ''|*[!0-9]*) exit 22;; esac
  [ "$old_pkg" = "$pkg" ] && [ "$old_port" = "$port" ] && [ "$old_cli_path" = "$cli" ] && [ "$old_process" = "$proc" ] || {
    echo FX_GADGET_SESSION_TARGET_CONFLICT
    exit 30
  }
  if kill -0 "$old_cli" 2>/dev/null; then
    old_cmd=$(tr '\000' ' ' < /proc/"$old_cli"/cmdline 2>/dev/null || :)
    case "$old_cmd" in *"$old_cli_path"*"-H"*"127.0.0.1:$port"*"-n"*Gadget*"-l"*"$script"*)
      echo FX_GADGET_SESSION_ALREADY_RUNNING
      exit 0;;
      *) echo FX_GADGET_SESSION_PID_CONFLICT; exit 23;;
    esac
  fi
fi
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
printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$cli_pid" "$feed_pid" "$cli" "$pkg" "$port" "$proc" > "$pid_tmp"
chmod 600 "$pid_tmp"
mv -f "$pid_tmp" "$pidfile"
[ "$(sed -n '3p' "$pidfile")" = "$cli" ] || { echo "FAIL: PID record line 3 must store CLI executable path" >&2; exit 1; }
[ "$(sed -n '6p' "$pidfile")" = "$proc" ] || { echo "FAIL: PID record line 6 must bind exact target process" >&2; exit 1; }
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
expected_pkg=$2
expected_cli=$3
expected_process=$4
port=27043
pidfile="$dir/gadget-$port.pid"
pipe="$dir/gadget-$port.stdin"
start_lock="$dir/.gadget-$port.start-lock"
[ ! -L "$start_lock" ] || { echo FX_GADGET_UNSAFE_START_LOCK; exit 29; }
mkdir "$start_lock" 2>/dev/null || { echo FX_GADGET_START_IN_PROGRESS; exit 26; }
lock_held=1
cleanup_stop() {
  [ "$lock_held" != 1 ] || rmdir "$start_lock" 2>/dev/null || :
}
trap cleanup_stop 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
[ ! -L "$pidfile" ] && [ ! -L "$pipe" ]
[ -s "$pidfile" ] || { echo FX_GADGET_SESSION_NOT_RUNNING; exit 0; }
cli_pid=$(sed -n '1p' "$pidfile")
feed_pid=$(sed -n '2p' "$pidfile")
cli=$(sed -n '3p' "$pidfile")
stored_pkg=$(sed -n '4p' "$pidfile")
stored_port=$(sed -n '5p' "$pidfile")
stored_process=$(sed -n '6p' "$pidfile")
case "$cli_pid:$feed_pid" in *[!0-9:]*|:*) exit 22;; esac
case "$stored_port" in ''|*[!0-9]*) exit 22;; esac
[ "$stored_pkg" = "$expected_pkg" ] && [ "$stored_port" = "$port" ] && [ "$stored_process" = "$expected_process" ] && [ "$cli" = "$expected_cli" ] || {
  echo FX_GADGET_SESSION_TARGET_CONFLICT
  exit 30
}
if kill -0 "$cli_pid" 2>/dev/null; then
  cmd=$(tr '\000' ' ' < /proc/"$cli_pid"/cmdline 2>/dev/null || :)
  case "$cmd" in *"$cli"*'127.0.0.1:27043'*Gadget*"$dir/gadget-$port.js"*) kill "$cli_pid";;
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
lock_held=0
rmdir "$start_lock"
echo FX_GADGET_SESSION_STOPPED
STOP
chmod 700 "$T/stop.sh"

if "$T/start.sh" "$T/frida" "com.example.debuggable" "$T/logs" "com.example.debuggable:missing" > "$T/missing-process.result" 2>&1; then
  echo "FAIL: Gadget start accepted a process that is not running" >&2
  exit 1
fi
grep -Fq FX_GADGET_TARGET_PROCESS_NOT_RUNNING "$T/missing-process.result"
if "$T/start.sh" "$T/frida" "com.example.debuggable" "$T/logs" "com.example.debuggable:spoof" > "$T/foreign-uid-process.result" 2>&1; then
  echo "FAIL: Gadget start accepted a same-name process owned by another UID" >&2
  exit 1
fi
grep -Fq FX_GADGET_TARGET_PROCESS_NOT_RUNNING "$T/foreign-uid-process.result"
"$T/start.sh" "$T/frida" "com.example.debuggable" "$T/logs" "com.example.debuggable:remote" > "$T/start.result"
grep -Fq "FX_GADGET_SESSION_STARTED" "$T/start.result"
sleep 0.2
grep -Fq "mock-send-message" "$T/logs/gadget-27043.log"
grep -Fq "mock-console-log" "$T/logs/gadget-27043.log"
[ -s "$T/logs/gadget-27043.pid" ] && [ -p "$T/logs/gadget-27043.stdin" ]
[ ! -d "$T/logs/.gadget-27043.start-lock" ]

# Stop and attach share one per-port lock. A concurrent start must block stop
# without killing either owned process or deleting the session record.
mkdir "$T/logs/.gadget-27043.start-lock"
if "$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida" "com.example.debuggable:remote" > "$T/busy-stop.result" 2>&1; then
  echo "FAIL: Gadget stop did not respect an active per-port start lock" >&2
  exit 1
fi
grep -Fq FX_GADGET_START_IN_PROGRESS "$T/busy-stop.result"
kill -0 "$(sed -n '1p' "$T/logs/gadget-27043.pid")" || {
  echo "FAIL: busy stop terminated the active Gadget CLI" >&2
  exit 1
}
[ -s "$T/logs/gadget-27043.pid" ] || {
  echo "FAIL: busy stop deleted the active session record" >&2
  exit 1
}
rmdir "$T/logs/.gadget-27043.start-lock"

if "$T/start.sh" "$T/frida" "com.example.other" "$T/logs" "com.example.debuggable:remote" > "$T/wrong-target-start.result" 2>&1; then
  echo "FAIL: Gadget reconnect accepted a different target package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-target-start.result"
if "$T/start.sh" "$T/frida" "com.example.debuggable" "$T/logs" "com.example.debuggable" > "$T/wrong-process-start.result" 2>&1; then
  echo "FAIL: Gadget reconnect accepted a different process in the same package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-process-start.result"
"$T/start.sh" "$T/frida" "com.example.debuggable" "$T/logs" "com.example.debuggable:remote" > "$T/reconnect.result"
grep -Fq FX_GADGET_SESSION_ALREADY_RUNNING "$T/reconnect.result"
kill -0 "$(sed -n '1p' "$T/logs/gadget-27043.pid")"

if "$T/stop.sh" "$T/logs" "com.example.other" "$T/frida" "com.example.debuggable:remote" > "$T/wrong-target-stop.result" 2>&1; then
  echo "FAIL: Gadget stop accepted a different target package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-target-stop.result"
if "$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida" "com.example.debuggable" > "$T/wrong-process-stop.result" 2>&1; then
  echo "FAIL: Gadget stop accepted a different process in the same package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-process-stop.result"
if "$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/not-the-frida-cli" "com.example.debuggable:remote" > "$T/wrong-cli-stop.result" 2>&1; then
  echo "FAIL: Gadget stop accepted a different Frida CLI identity" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-cli-stop.result"
kill -0 "$(sed -n '1p' "$T/logs/gadget-27043.pid")" || {
  echo "FAIL: wrong-target stop terminated the active session" >&2
  exit 1
}
"$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida" "com.example.debuggable:remote" > "$T/stop.result"
grep -Fq FX_GADGET_SESSION_STOPPED "$T/stop.result"
[ ! -e "$T/logs/gadget-27043.pid" ] && [ ! -e "$T/logs/gadget-27043.stdin" ]
[ -z "$(find "$T/logs" -maxdepth 1 -name '.gadget-27043.*' -print -quit)" ] || {
  echo "FAIL: temporary Gadget session script/PID file leaked" >&2
  exit 1
}
echo "PASS: Frida CLI mock stays attached, records session output and stops only the recorded CLI/feeder processes"
