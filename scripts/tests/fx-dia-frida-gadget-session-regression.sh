#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
SESSION_LOG="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java"
ROOT_ACCESS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java"
[ -s "$ACTIVITY" ] || { echo "FAIL: Dia Frida Activity source missing" >&2; exit 1; }
[ -s "$SESSION_LOG" ] || { echo "FAIL: Dia Frida session log Activity source missing" >&2; exit 1; }
[ -s "$ROOT_ACCESS" ] || { echo "FAIL: RootAccess source missing" >&2; exit 1; }

python3 - "$ACTIVITY" "$SESSION_LOG" "$ROOT_ACCESS" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
session_log = Path(sys.argv[2]).read_text(encoding="utf-8")
root_access = Path(sys.argv[3]).read_text(encoding="utf-8")
session_log_compact = " ".join(session_log.split())
assert "new ThreadPoolExecutor( 1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1)" in session_log_compact, "session log reads must use a single bounded worker"
assert "new ThreadPoolExecutor.AbortPolicy()" in session_log, "session log worker must reject overload explicitly"
assert "catch (RejectedExecutionException full)" in session_log, "session log UI must report queue saturation"
assert "worker.shutdownNow();" in session_log, "session log worker must stop with Activity lifecycle"
required = {
    "Gadget attach action is reachable from UI": 'button("连接 Gadget、加载当前脚本并恢复 WAIT", () -> attachToGadgetAndResume())',
    "Gadget message/console log action is reachable from UI": 'button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog())',
    "Gadget session stop action is reachable from UI": 'button("停止 Gadget 会话", () -> stopGadgetSession())',
    "Gadget session status refresh is reachable from UI": 'button("刷新 Gadget 会话状态", () -> checkGadgetSession())',
    "Gadget session status checker exists": "private void checkGadgetSession()",
    "separate Frida CLI path helper": "currentFridaCliPath()",
    "attach validates CLI executable path": "if (!validPath(cli))",
    "target is revalidated as debuggable": "ApplicationInfo.FLAG_DEBUGGABLE",
    "system packages are excluded": "ApplicationInfo.FLAG_SYSTEM",
    "target process must be running": "FX_GADGET_TARGET_NOT_RUNNING",
    "Gadget target process validator is called": "validateProcessName(targetPackage, process)",
    "target UID is captured from PackageManager": "targetUid = targetInfo.uid",
    "process enumeration uses a PID-only ps listing": "ps -A -o PID 2>/dev/null",
    "process name is read from the full proc cmdline": r'\"$proc_root/$pid/cmdline\"',
    "proc argv0 matches the selected process exactly": r'\"$proc_name\" = \"$process\"',
    "process enumeration verifies target app UID": r'\"$uid\" = \"$target_uid\"',
    "process UID comes from proc status": r'\"$proc_root/$pid/status\"',
    "Frida source staging helper is invoked": "stageFridaRootInput(source)",
    "Frida source is staged in app-private cache": 'File.createTempFile("fx-dia-frida-input-", ".js", cache)',
    "Frida source is written in bounded UTF-8 chunks": "writer.write(source, offset, count)",
    "staged source is read as a private file stream": "new java.io.FileInputStream(inputFile)",
    "large Frida source streams through RootAccess stdin": "RootAccess.executeWithInput(command, input, timeout",
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
    "stop waits for owned CLI and feeder to exit": "pid_active()",
    "stop timeout does not discard ownership record": "FX_GADGET_STOP_TIMEOUT",
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
        "Gadget WAIT/RESUME config semantics remain": 'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget rejects frida-server port": "if (port == 27042)",
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")
root_access_compact = " ".join(root_access.split())
if "executeWithInput(String command, java.io.InputStream input" not in root_access_compact:
    raise SystemExit("FAIL: RootAccess accepts InputStream payloads: missing streaming overload")
if "byte[] buffer = new byte[64 * 1024]" not in root_access:
    raise SystemExit("FAIL: RootAccess writes payload in bounded chunks")
for label, needle in {
    "staged source is tracked for cleanup": "pendingRootInputFiles.add(staged)",
    "failed staging removes partial files": "if (!complete) staged.delete()",
    "Root transfer validates private cache ownership": "isPrivateFridaRootInput(inputFile)",
    "Root transfer removes staged files": "deleteFridaRootInput(inputFile)",
    "Activity teardown removes pending source files": "for (File pendingInput : new ArrayList<>(pendingRootInputFiles))",
}.items():
    if needle not in source:
        raise SystemExit(f"FAIL: Frida file-stream lifecycle missing {label}")
if "MAX_FRIDA_SOURCE_BYTES" in source or "sourceBytes.length >" in source:
    raise SystemExit("FAIL: Frida runtime still has an arbitrary script-size ceiling")
if "input.length > 8 * 1024 * 1024" in root_access:
    raise SystemExit("FAIL: RootAccess still caps streamed script payloads at 8 MiB")
assert "if (code == 0) code = 5;" in root_access, "Root stdin writer failure must prevent a false-success result"
assert "cat >/dev/null; echo FX_GADGET_SESSION_ALREADY_RUNNING" in source, "already-running Gadget path must drain streamed input before returning success"
assert "if (code == 0) code = 5;" in root_access, "Root stdin writer failure must prevent a false-success result"
assert "cat >/dev/null; echo FX_GADGET_SESSION_ALREADY_RUNNING" in source, "already-running Gadget path must drain streamed input before returning success"
attach = source[source.index("private void attachToGadgetAndResume()"):
                 source.index("private void stopGadgetSession()")]
check = source[source.index("private void checkGadgetSession()"):source.index("private void stopGadgetSession()")]
stop = source[source.index("private void stopGadgetSession()"):
               source.index("private void showGadgetSessionLog()")]

for label, needle in (
    ("status checker rejects symlinked session directories", '[ ! -L \\"$dir\\" ]'),
    ("status checker rejects symlinked PID records", "FX_GADGET_PIDFILE_SYMLINK_REJECTED"),
    ("status checker validates stored target identity", "FX_GADGET_SESSION_TARGET_CONFLICT"),
    ("status checker verifies live PID state", "pid_active()"),
    ("status checker validates CLI command identity", "FX_GADGET_CLI_PID_CONFLICT"),
    ("status checker validates stdin feeder identity", "FX_GADGET_FEEDER_PID_CONFLICT"),
    ("status checker distinguishes degraded and stale sessions", "FX_GADGET_SESSION_DEGRADED"),
):
    if needle not in check:
        raise SystemExit(f"FAIL: Gadget session status contract missing: {label}")
if "rm -f" in check or 'kill "$' in check:
    raise SystemExit("FAIL: Gadget session status checker must be read-only")
show = source[source.index("private void showGadgetSessionLog()"):
               source.index("private void copyGadgetConnectCommand()")]
for label, needle in (
    ("Gadget log page route passes only the selected port", 'page.putExtra("fx_dia_session_log_gadget_port", port)'),
    ("Gadget log page route uses the native viewer", "FxDiaSessionLogActivity.class"),
):
    if needle not in show:
        raise SystemExit(f"FAIL: Gadget session log route missing: {label}")
for label, needle in (
    ("Gadget log path is built from the validated port", 'LOG_DIR + "/gadget-" + gadgetPort + ".log"'),
    ("Gadget log port excludes invalid values and frida-server default", "gadgetPort >= 1024 && gadgetPort <= 65535 && gadgetPort != 27042"),
    ("Gadget log reads remain bounded", "tail -n 500"),
    ("Gadget log reads reject symlink files", '&& [ ! -L " + quote(logPath)'),
    ("Gadget log clear remains confirmation gated", 'setTitle("清空 Frida 会话日志")'),
):
    if needle not in session_log:
        raise SystemExit(f"FAIL: Native Gadget session log safety missing: {label}")
logs_guard = source[source.index("private String prepareDiaLogsDirectoryPrefix()"):
                    source.index("private String checkedSessionLogDirectoryPrefix()")]
existing_guard = source[source.index("private String checkedSessionLogDirectoryPrefix()"):
                        source.index("private void showSessionLog()")]
if "prepareDiaLogsDirectoryPrefix()" not in attach:
    raise SystemExit("FAIL: Gadget attach must preflight/create/check the entire Frida log directory chain")
if "checkedSessionLogDirectoryPrefix()" not in stop:
    raise SystemExit("FAIL: Gadget stop must reject symlinks in every parent directory")
for label, needle in (
    ("Gadget parent guard checks real /data and /data/adb directories", "for path in /data /data/adb; do"),
    ("Gadget parent guard rejects symlink ancestors before mkdir", "! -L "),
    ("Gadget parent guard verifies directories after mkdir", "[ -d "),
    ("Gadget parent guard has explicit fail-closed status", "FX_DIA_LOG_UNSAFE_PARENT"),
):
    if needle not in logs_guard:
        raise SystemExit(f"FAIL: {label}")
for label, needle in (
    ("read/stop guard defines the FX base directory", 'String baseDir = "/data/adb/privacyguard";'),
    ("read/stop guard validates the Dia directory", 'String diaDir = baseDir + "/dia-frida";'),
    ("read/stop guard validates the logs directory", 'String logDir = diaDir + "/logs";'),
    ("read/stop guard checks the /data/adb parent", "if [ -L '/data/adb' ]"),
    ("read/stop guard emits explicit failure marker", "FX_DIA_LOG_PATH_UNAVAILABLE"),
    ("read/stop guard quotes the base directory", "quote(baseDir)"),
    ("read/stop guard quotes the Dia directory", "quote(diaDir)"),
    ("read/stop guard quotes the logs directory", "quote(logDir)"),
):
    if needle not in existing_guard:
        raise SystemExit(f"FAIL: {label}")
root_worker = source[source.index("private final ThreadPoolExecutor worker ="):
                      source.index("private void ensureFridaWorkerActive()")]
root_worker_compact = " ".join(root_worker.split())
if "ThreadPoolExecutor( 1, 1, 30L" not in root_worker_compact or "new ArrayBlockingQueue<>(12)" not in root_worker_compact:
    raise SystemExit("FAIL: Frida Root operations must share one bounded serial worker")
if "new ThreadPoolExecutor.AbortPolicy()" not in root_worker:
    raise SystemExit("FAIL: Frida Root worker must reject overload explicitly")
if "submitWorker(() ->" not in source[source.index("private void runRoot("):
                                   source.index("private void setStatus(")]:
    raise SystemExit("FAIL: Frida Root commands must route through the shared bounded worker")
if "catch (RejectedExecutionException full)" not in source:
    raise SystemExit("FAIL: Frida UI must surface queue saturation")
if "worker.shutdownNow();" not in source[source.index("@Override protected void onDestroy()"):]:
    raise SystemExit("FAIL: Frida Root worker must stop with Activity lifecycle")
if "ps -A -o PID,NAME" in attach:
    raise SystemExit("FAIL: Gadget process matching must not rely on the ps NAME column")
if "session_pid_active()" not in attach or "Z|X|x" not in attach:
    raise SystemExit("FAIL: Gadget reattach must treat zombie/dead recorded PIDs as exited")
if attach.count("session_pid_active") < 3:
    raise SystemExit("FAIL: both recorded CLI and feeder PIDs must use the same zombie-aware liveness guard")
if 'if kill -0 \\"$old_cli\\"' in attach or '&& kill -0 \\"$old_feed\\"' in attach:
    raise SystemExit("FAIL: reattach must not use kill -0 alone for old Gadget session ownership")
if 'if session_pid_active \\"$old_feed\\"; then' not in attach:
    raise SystemExit("FAIL: active Gadget CLI must not be accepted without a live stdin feeder")
if "FX_GADGET_FEEDER_PID_CONFLICT" not in attach or "FX_GADGET_SESSION_DEGRADED" not in attach:
    raise SystemExit("FAIL: reattach must distinguish a foreign feeder from a degraded CLI-only session")
if "currentInjectorPath()" in attach or "String injector" in attach:
    raise SystemExit("FAIL: remote Gadget session must use frida CLI, not the frida-inject binary")
if "Runtime.exec" in attach:
    raise SystemExit("FAIL: Frida attach must not bypass the bounded RootAccess command bridge")
if "runRootWithInput(command, sourceInput, 20000L" not in attach:
    raise SystemExit("FAIL: persistent Gadget command must stream its file-backed source through RootAccess")
if "state=${state##*) }" not in attach or "Z|X|x) exit 0" not in attach or "fx-gadget-feed-$port" not in attach:
    raise SystemExit("FAIL: FIFO feeder must stop on CLI zombie/dead state and retain its fixed port-specific identity")
for process_id in ("cli_pid", "feed_pid"):
    escaped_kill = 'kill \\"$' + process_id + '\\"'
    if escaped_kill not in stop:
        raise SystemExit(f"FAIL: session stop must terminate the owned {process_id} process")
if "FX_GADGET_CLI_PID_CONFLICT" not in stop or "FX_GADGET_FEEDER_PID_CONFLICT" not in stop:
    raise SystemExit("FAIL: stop path must refuse unrelated PID owners")
if "pid_active()" not in stop or "FX_GADGET_STOP_TIMEOUT" not in stop:
    raise SystemExit("FAIL: stop path must verify CLI/feeder process exit before removing the session record")
if stop.index("FX_GADGET_STOP_TIMEOUT") > stop.index("rm -f \\\"$pidfile\\\""):
    raise SystemExit("FAIL: stop timeout check must happen before deleting the PID record")
if "final String expectedCli = currentFridaCliPath();" not in stop:
    raise SystemExit("FAIL: stop path must bind to the currently configured Frida CLI")
if 'start_lock=" + quote(startLockPath)' not in stop or "trap cleanup_stop 0" not in stop:
    raise SystemExit("FAIL: stop path must hold the same per-port lock as attach")
if '[ \\"$cli\\" = \\"$expected_cli\\" ]' not in stop:
    raise SystemExit("FAIL: stop path must compare the recorded CLI path, not the Gadget JS path")
print("PASS: Frida CLI Gadget session validates target/port/CLI identity, owns a persistent process, captures logs and provides a PID-checked stop action")
PY

# Trace the local process/UID/FIFO lifecycle fixture. Source-contract checks above
# are intentionally separate from this behavioral simulation.
set -x
echo "GADGET_SESSION_TEST_STAGE: local UID/process fixture"

# Exercise a long-lived remote Frida CLI session with a local mock. This validates
# FIFO lifetime, argument contract, PID ownership checks and cleanup; it does not
# claim Android-device Frida compatibility.
T=$(mktemp -d "/tmp/fx-dia-gadget-session.XXXXXX")
cleanup(){
  if [ -n "${zombie_parent:-}" ]; then kill "$zombie_parent" 2>/dev/null || :; wait "$zombie_parent" 2>/dev/null || :; fi
  if [ -s "$T/logs/gadget-27043.pid" ]; then
    cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid")
    feed_pid=$(sed -n '2p' "$T/logs/gadget-27043.pid")
    kill -KILL "$cli_pid" "$feed_pid" 2>/dev/null || :
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
printf '  PID\n'
printf '12345\n'
printf '12346\n'
printf '12347\n'
PS
chmod 700 "$T/bin/ps"
mkdir -p "$T/proc/12345" "$T/proc/12346" "$T/proc/12347"
printf 'Name: com.example.debuggable\nUid: 10002 10002 10002 10002\n' > "$T/proc/12345/status"
printf 'Name: com.example.debuggable:remote\nUid: 10002 10002 10002 10002\n' > "$T/proc/12346/status"
# Keep the full process name in proc cmdline even though ps only returns PIDs.
printf 'com.example.debuggable\000' > "$T/proc/12345/cmdline"
printf 'com.example.debuggable:remote\000' > "$T/proc/12346/cmdline"
# Same process name shape, but a different app UID; the UID check must reject it.
printf 'Name: com.example.debuggable:spoof\nUid: 10099 10099 10099 10099\n' > "$T/proc/12347/status"
printf 'com.example.debuggable:spoof\000' > "$T/proc/12347/cmdline"
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
IGNORE_TERM=0
if [ "$IGNORE_TERM" = "1" ]; then
  trap '' TERM
  printf 'mock-ignore-term-ready\n'
fi
# Keep the CLI alive with TERM explicitly ignored; the stop path must preserve
# its PID record after the bounded wait instead of pretending it stopped.
while :; do sleep 1; done
MOCK
chmod 700 "$T/frida"
sed 's/^IGNORE_TERM=0$/IGNORE_TERM=1/' "$T/frida" > "$T/frida-ignore-term"
chmod 700 "$T/frida-ignore-term"

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
pids=$(ps -A -o PID 2>/dev/null | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' | while IFS= read -r pid; do
  proc_name=$(tr '\000' '\n' < "$proc_root/$pid/cmdline" 2>/dev/null | sed -n '1p')
  [ "$proc_name" = "$proc" ] || continue
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
session_pid_active() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
  state=$(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | cut -d ' ' -f1)
  case "$state" in Z|X|x) return 1;; esac
  kill -0 "$1" 2>/dev/null
}
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
  if session_pid_active "$old_cli"; then
    old_cmd=$(tr '\000' ' ' < /proc/"$old_cli"/cmdline 2>/dev/null || :)
    case "$old_cmd" in *"$old_cli_path"*"-H"*"127.0.0.1:$port"*"-n"*Gadget*"-l"*"$script"*)
      if session_pid_active "$old_feed"; then
        feed_cmd=$(tr '\000' ' ' < /proc/"$old_feed"/cmdline 2>/dev/null || :)
        case "$feed_cmd" in *"fx-gadget-feed-$port"*"$pipe"*)
          cat >/dev/null
          echo FX_GADGET_SESSION_ALREADY_RUNNING
          exit 0;;
          *) echo FX_GADGET_FEEDER_PID_CONFLICT; exit 24;;
        esac
      fi
      echo FX_GADGET_SESSION_DEGRADED
      exit 32;;
      *) echo FX_GADGET_SESSION_PID_CONFLICT; exit 23;;
    esac
  fi
  if [ -n "$old_feed" ] && session_pid_active "$old_feed"; then
    feed_cmd=$(tr '\000' ' ' < /proc/"$old_feed"/cmdline 2>/dev/null || :)
    case "$feed_cmd" in *"fx-gadget-feed-$port"*"$pipe"*)
      kill "$old_feed" 2>/dev/null || :
      _feed_wait=0
      while session_pid_active "$old_feed"; do
        [ "$_feed_wait" -lt 5 ] || { echo FX_GADGET_FEEDER_STOP_TIMEOUT; exit 26; }
        sleep 1
        _feed_wait=$((_feed_wait+1))
      done;;
      *) echo FX_GADGET_FEEDER_PID_CONFLICT; exit 24;;
    esac
  fi
  rm -f "$pidfile"
  if [ -e "$pipe" ]; then
    [ -p "$pipe" ] || { echo FX_GADGET_UNSAFE_STALE_PIPE; exit 27; }
    rm -f "$pipe"
  fi
elif [ -e "$pipe" ]; then
  echo FX_GADGET_ORPHAN_PIPE_NEEDS_CLEANUP
  exit 28
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
nohup sh -c 'while :; do state=$(cat "/proc/$1/stat" 2>/dev/null); state=${state##*) }; state=${state%% *}; case "$state" in Z|X|x) exit 0;; esac; kill -0 "$1" 2>/dev/null || exit 0; sleep 1; done' "fx-gadget-feed-$port" "$cli_pid" "$pipe" > "$pipe" 2>/dev/null < /dev/null &
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
pid_active() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
  state=$(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | cut -d ' ' -f1)
  case "$state" in Z|X) return 1;; esac
  kill -0 "$1" 2>/dev/null
}
if pid_active "$cli_pid"; then
  cmd=$(tr '\000' ' ' < /proc/"$cli_pid"/cmdline 2>/dev/null || :)
  case "$cmd" in *"$cli"*'127.0.0.1:27043'*Gadget*"$dir/gadget-27043.js"*) kill "$cli_pid";;
    *) echo FX_GADGET_CLI_PID_CONFLICT; exit 23;;
  esac
fi
if pid_active "$feed_pid"; then
  feed_cmd=$(tr '\000' ' ' < /proc/"$feed_pid"/cmdline 2>/dev/null || :)
  case "$feed_cmd" in *"fx-gadget-feed-27043"*"$pipe"*) kill "$feed_pid";;
    *) echo FX_GADGET_FEEDER_PID_CONFLICT; exit 24;;
  esac
fi
_stop_wait=0
while pid_active "$cli_pid" || pid_active "$feed_pid"; do
  [ "$_stop_wait" -lt 5 ] || { echo FX_GADGET_STOP_TIMEOUT; exit 31; }
  sleep 1
  _stop_wait=$((_stop_wait+1))
done
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
# A real zombie child must be treated as exited by the feeder itself.
python3 -c 'import os,time; p=os.fork(); (os._exit(0) if p == 0 else None); print(p, flush=True); time.sleep(10)' > "$T/zombie-child.pid" &
zombie_parent=$!
_zombie_wait=0
while [ ! -s "$T/zombie-child.pid" ]; do
  [ "$_zombie_wait" -lt 20 ] || { echo "FAIL: zombie parent did not publish child PID" >&2; exit 1; }
  sleep 0.05
  _zombie_wait=$((_zombie_wait+1))
done
zombie_cli=$(cat "$T/zombie-child.pid")
_zombie_wait=0
while :; do
  zombie_record=$(cat "/proc/$zombie_cli/stat" 2>/dev/null)
  zombie_state=${zombie_record##*) }
  zombie_state=${zombie_state%% *}
  [ "$zombie_state" = Z ] && break
  [ "$_zombie_wait" -lt 20 ] || { echo "FAIL: could not create zombie CLI fixture" >&2; exit 1; }
  sleep 0.05
  _zombie_wait=$((_zombie_wait+1))
done
mkfifo "$T/zombie-feeder.stdin"
nohup sh -c 'while :; do state=$(cat "/proc/$1/stat" 2>/dev/null); state=${state##*) }; state=${state%% *}; case "$state" in Z|X|x) exit 0;; esac; kill -0 "$1" 2>/dev/null || exit 0; sleep 1; done' "fx-gadget-feed-zombie-test" "$zombie_cli" "$T/zombie-feeder.stdin" > "$T/zombie-feeder.stdin" 2>/dev/null < /dev/null &
zombie_feeder=$!
_zombie_wait=0
while kill -0 "$zombie_feeder" 2>/dev/null; do
  [ "$_zombie_wait" -lt 20 ] || { echo "FAIL: feeder remained alive for zombie CLI" >&2; exit 1; }
  sleep 0.05
  _zombie_wait=$((_zombie_wait+1))
done
wait "$zombie_feeder" 2>/dev/null || :
kill "$zombie_parent" 2>/dev/null || :
wait "$zombie_parent" 2>/dev/null || :
zombie_parent=

rm -f "$T/zombie-feeder.stdin"

"$T/start.sh" "$T/frida-ignore-term" "com.example.debuggable" "$T/logs" "com.example.debuggable:remote" > "$T/start.result"
grep -Fq "FX_GADGET_SESSION_STARTED" "$T/start.result"
sleep 0.2
grep -Fq "mock-send-message" "$T/logs/gadget-27043.log"
grep -Fq "mock-console-log" "$T/logs/gadget-27043.log"
grep -Fq "mock-ignore-term-ready" "$T/logs/gadget-27043.log" || { echo "FAIL: mock CLI did not confirm that TERM is ignored" >&2; exit 1; }
[ -s "$T/logs/gadget-27043.pid" ] && [ -p "$T/logs/gadget-27043.stdin" ]
[ ! -d "$T/logs/.gadget-27043.start-lock" ]

# Stop and attach share one per-port lock. A concurrent start must block stop
# without killing either owned process or deleting the session record.
mkdir "$T/logs/.gadget-27043.start-lock"
if "$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida-ignore-term" "com.example.debuggable:remote" > "$T/busy-stop.result" 2>&1; then
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

if "$T/start.sh" "$T/frida-ignore-term" "com.example.other" "$T/logs" "com.example.debuggable:remote" > "$T/wrong-target-start.result" 2>&1; then
  echo "FAIL: Gadget reconnect accepted a different target package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-target-start.result"
if "$T/start.sh" "$T/frida-ignore-term" "com.example.debuggable" "$T/logs" "com.example.debuggable" > "$T/wrong-process-start.result" 2>&1; then
  echo "FAIL: Gadget reconnect accepted a different process in the same package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-process-start.result"
"$T/start.sh" "$T/frida-ignore-term" "com.example.debuggable" "$T/logs" "com.example.debuggable:remote" > "$T/reconnect.result"
grep -Fq FX_GADGET_SESSION_ALREADY_RUNNING "$T/reconnect.result"
kill -0 "$(sed -n '1p' "$T/logs/gadget-27043.pid")"

if "$T/stop.sh" "$T/logs" "com.example.other" "$T/frida-ignore-term" "com.example.debuggable:remote" > "$T/wrong-target-stop.result" 2>&1; then
  echo "FAIL: Gadget stop accepted a different target package" >&2
  exit 1
fi
grep -Fq FX_GADGET_SESSION_TARGET_CONFLICT "$T/wrong-target-stop.result"
if "$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida-ignore-term" "com.example.debuggable" > "$T/wrong-process-stop.result" 2>&1; then
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
cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid")
if "$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida-ignore-term" "com.example.debuggable:remote" > "$T/timeout-stop.result" 2>&1; then
  echo "FAIL: Gadget stop discarded its record while the owned CLI ignored TERM" >&2
  exit 1
fi
grep -Fq FX_GADGET_STOP_TIMEOUT "$T/timeout-stop.result"
[ -s "$T/logs/gadget-27043.pid" ] && [ -p "$T/logs/gadget-27043.stdin" ] || {
  echo "FAIL: timed-out stop must retain the session record and FIFO for recovery" >&2
  exit 1
}
kill -KILL "$cli_pid" 2>/dev/null || :
# Simulate a stale but still-owned feeder after its CLI has exited. Reattach
# must terminate it and wait; it must not unlink the FIFO while it is alive.
sleep 1.2
nohup sh -c 'trap "" TERM; while :; do sleep 1; done' \
  "fx-gadget-feed-27043" "$cli_pid" "$T/logs/gadget-27043.stdin" \
  > /dev/null 2>&1 < /dev/null &
stale_feed=$!
pid_tmp=$(mktemp "$T/logs/.gadget-27043.pid.XXXXXX")
{
  printf '%s\n%s\n' "$cli_pid" "$stale_feed"
  tail -n +3 "$T/logs/gadget-27043.pid"
} > "$pid_tmp"
chmod 600 "$pid_tmp"
mv -f "$pid_tmp" "$T/logs/gadget-27043.pid"
if "$T/start.sh" "$T/frida-ignore-term" "com.example.debuggable" "$T/logs" "com.example.debuggable:remote" > "$T/feeder-timeout.result" 2>&1; then
  echo "FAIL: reattach replaced a FIFO while its stale feeder ignored TERM" >&2
  exit 1
fi
grep -Fq FX_GADGET_FEEDER_STOP_TIMEOUT "$T/feeder-timeout.result"
[ -s "$T/logs/gadget-27043.pid" ] && [ -p "$T/logs/gadget-27043.stdin" ] || {
  echo "FAIL: feeder stop timeout must preserve the session record and FIFO" >&2
  exit 1
}
kill -KILL "$stale_feed" 2>/dev/null || :
wait "$stale_feed" 2>/dev/null || :
_wait=0
while kill -0 "$stale_feed" 2>/dev/null; do
  [ "$_wait" -lt 5 ] || { echo "FAIL: stale feeder did not exit after KILL" >&2; exit 1; }
  sleep 1
  _wait=$((_wait+1))
done
"$T/start.sh" "$T/frida-ignore-term" "com.example.debuggable" "$T/logs" "com.example.debuggable:remote" > "$T/recovered-start.result"
grep -Fq FX_GADGET_SESSION_STARTED "$T/recovered-start.result"
cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid")
"$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida-ignore-term" "com.example.debuggable:remote" > "$T/stop.result" || :
grep -Fq FX_GADGET_STOP_TIMEOUT "$T/stop.result"
kill -KILL "$cli_pid" 2>/dev/null || :
"$T/stop.sh" "$T/logs" "com.example.debuggable" "$T/frida-ignore-term" "com.example.debuggable:remote" > "$T/stop.result"
grep -Fq FX_GADGET_SESSION_STOPPED "$T/stop.result"
[ ! -e "$T/logs/gadget-27043.pid" ] && [ ! -e "$T/logs/gadget-27043.stdin" ]
[ -z "$(find "$T/logs" -maxdepth 1 -name '.gadget-27043.*' -print -quit)" ] || {
  echo "FAIL: temporary Gadget session script/PID file leaked" >&2
  exit 1
}
echo "PASS: Frida CLI mock stays attached, records session output and stops only the recorded CLI/feeder processes"

# Exercise RootAccess itself with a payload larger than the former 8 MiB limit.
# The fake su broker runs the supplied command locally; this verifies the Java
# InputStream writer, byte integrity, and writer-failure propagation without
# claiming Android KernelSU execution.
STREAM_TEST="$T/RootAccessStreamHostTest.java"
STREAM_CLASSES="$T/root-access-classes"
mkdir -p "$STREAM_CLASSES" "$T/fake-su"
cat > "$T/fake-su/su" <<'SU'
#!/bin/sh
[ "$1" = "-c" ] || exit 2
exec /bin/sh -c "$2"
SU
chmod 700 "$T/fake-su/su"
cat > "$STREAM_TEST" <<'JAVA'
package de.privacyguard.adhook;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;

public final class RootAccessStreamHostTest {
    private static String sha256(Path path) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = Files.newInputStream(path)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        StringBuilder value = new StringBuilder();
        for (byte b : digest.digest()) value.append(String.format("%02x", b & 0xff));
        return value.toString();
    }

    private static String quote(Path path) {
        return "'" + path.toAbsolutePath().toString().replace("'", "'\\''") + "'";
    }

    public static void main(String[] args) throws Exception {
        Path dir = Paths.get(args[0]);
        Path source = dir.resolve("source.bin");
        Path destination = dir.resolve("destination.bin");
        try (OutputStream output = Files.newOutputStream(source)) {
            byte[] block = new byte[64 * 1024];
            for (int i = 0; i < block.length; i++) block[i] = (byte) (i * 31 + 7);
            for (int i = 0; i < 9 * 1024 * 1024 / block.length; i++) output.write(block);
        }
        String expected = sha256(source);
        String command = "cat > " + quote(destination) + " && sha256sum " + quote(destination);
        RootAccess.Result copied;
        try (InputStream input = new FileInputStream(source.toFile())) {
            copied = RootAccess.executeWithInput(command, input, 30000L, 4096);
        }
        if (copied.exitCode != 0 || copied.output == null || !copied.output.contains(expected))
            throw new AssertionError("9 MiB streamed payload integrity failed: " + copied.exitCode + " " + copied.output);
        if (Files.size(source) != Files.size(destination))
            throw new AssertionError("streamed payload size changed");

        InputStream broken = new InputStream() {
            @Override public int read() throws IOException { throw new IOException("synthetic stream failure"); }
        };
        RootAccess.Result failed = RootAccess.executeWithInput("cat >/dev/null", broken, 10000L, 4096);
        if (failed.exitCode == 0 || failed.output == null || !failed.output.contains("Root stdin 写入失败"))
            throw new AssertionError("stdin writer failure was reported as success: " + failed.exitCode + " " + failed.output);
        Path capturedOutput = dir.resolve("root-output-over-one-mib.bin");
        RootAccess.Result captured = RootAccess.executeToFile(
                "head -c 2097152 /dev/zero", 30000L, capturedOutput.toFile());
        if (captured.exitCode != 0 || !Files.isRegularFile(capturedOutput)
                || Files.size(capturedOutput) != 2L * 1024L * 1024L) {
            throw new AssertionError("RootAccess did not stream >1 MiB stdout to a file: "
                    + captured.exitCode + " " + captured.output);
        }
        try (InputStream input = Files.newInputStream(capturedOutput)) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                for (int i = 0; i < count; i++) {
                    if (buffer[i] != 0) {
                        throw new AssertionError("file-backed Root stdout corrupted output bytes");
                    }
                }
            }
        }
        System.out.println("PASS: RootAccess streams a 9 MiB stdin payload, fails closed on writer errors, and captures >1 MiB stdout to a file");
    }
}
JAVA
command -v javac >/dev/null 2>&1 || { echo "FAIL: javac is required for RootAccess stream host test" >&2; exit 1; }
command -v java >/dev/null 2>&1 || { echo "FAIL: java is required for RootAccess stream host test" >&2; exit 1; }
javac -d "$STREAM_CLASSES" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" "$STREAM_TEST"
PATH="$T/fake-su:$PATH" java -cp "$STREAM_CLASSES" de.privacyguard.adhook.RootAccessStreamHostTest "$T"
