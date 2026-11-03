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
    "Gadget attach action is reachable from the UI":
        'button("连接 Gadget、加载当前脚本并恢复 WAIT", () -> attachToGadgetAndResume())',
    "Gadget stop action is reachable from the UI":
        'button("停止 Gadget 会话", () -> stopGadgetSession())',
    "Gadget log action is reachable from the UI":
        'button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog())',
    "Frida CLI has its own persisted path":
        'putString("frida_cli_path", cli)',
    "Frida CLI path is validated before use":
        'if (!validPath(cli))',
    "Frida CLI is checked for executability":
        'test -x "$cli" && test ! -L "$cli"',
    "Frida CLI version is checked":
        '"$cli" --version',
    "Frida CLI receives loopback endpoint":
        '"$cli" -H "127.0.0.1:$port"',
    "Frida CLI attaches to Gadget by name":
        '-n Gadget -l "$script"',
    "Gadget command uses a private persistent stdin FIFO":
        'mkfifo -m 600 "$pipe"',
    "Gadget CLI is detached from the Root command timeout":
        'nohup "$cli"',
    "Gadget FIFO writer is owned and tracked":
        'nohup tail -f /dev/null > "$pipe"',
    "Gadget session record is atomically installed":
        'mv -f "$pid_tmp" "$pidfile"',
    "Gadget session lock prevents duplicate attach":
        'start_lock="$dir/.gadget-$port.start-lock"',
    "session validates stale CLI ownership":
        'FX_GADGET_SESSION_PID_CONFLICT',
    "session validates stale feeder ownership":
        'FX_GADGET_FEEDER_PID_CONFLICT',
    "session refuses unsafe log/pipe/script symlinks":
        'FX_GADGET_UNSAFE_SESSION_PATH',
    "target is revalidated as debuggable before remote control":
        'targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE',
    "system packages are excluded":
        'targetInfo.flags & ApplicationInfo.FLAG_SYSTEM',
    "target package must currently be running":
        'FX_GADGET_TARGET_NOT_RUNNING',
    "process enumeration is package-scoped":
        'index($2,pkg',
    "Frida source is bounded":
        'sourceBytes.length > 48 * 1024',
    "Frida source rejects NUL":
        'source.indexOf(0) >= 0',
    "script is staged using an unpredictable same-directory temp":
        '.gadget-$port.XXXXXX',
    "Root runtime defaults to private permissions":
        'umask 077',
    "script, log, pipe and pid records are owner-only":
        'chmod 600',
    "Gadget log directory is restricted":
        'chmod 700',
    "Gadget session output is captured":
        '>> "$log" 2>&1',
    "log viewer reads a bounded tail":
        'tail -n 500',
    "Gadget config preserves WAIT/RESUME semantics":
        'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget config rejects frida-server port":
        'if (port == 27042)',
    "stop path validates CLI PID against exact CLI/endpoint":
        'FX_GADGET_CLI_PID_CONFLICT',
    "stop path validates feeder PID ownership":
        'FX_GADGET_FEEDER_PID_CONFLICT',
    "stop path removes session record and FIFO":
        'FX_GADGET_SESSION_STOPPED',
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

attach = source[source.index("private void attachToGadgetAndResume()"):
                 source.index("private void stopGadgetSession()")]
stop = source[source.index("private void stopGadgetSession()"):
               source.index("private void showGadgetSessionLog()")]
if "0.0.0.0" in attach or "0.0.0.0" in stop:
    raise SystemExit("FAIL: Gadget remote control must stay bound to loopback")
if "frida-inject" in attach:
    raise SystemExit("FAIL: remote CLI session must not use frida-inject")
if 'Runtime.exec' in attach or 'sh -c' in attach:
    raise SystemExit("FAIL: Frida attach must use the bounded RootAccess command bridge")
if "FLAG_DEBUGGABLE" not in attach or "FLAG_SYSTEM" not in attach:
    raise SystemExit("FAIL: target eligibility checks were removed")
if "kill " not in stop or "/proc/" not in stop:
    raise SystemExit("FAIL: session stop must validate process command lines before signalling")
print("PASS: Dia Frida Gadget CLI path, persistent session, process ownership and bounded log contracts")
PY

# A local mock exercises the actual persistent CLI/FIFO shape. It is host-side
# shell integration evidence only; it does not claim a real Android Gadget attach.
T=$(mktemp -d "/tmp/fx-dia-gadget-session.XXXXXX")
cleanup(){
  if [ -s "$T/logs/gadget-27043.pid" ]; then
    cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid" 2>/dev/null || :)
    feed_pid=$(sed -n '2p' "$T/logs/gadget-27043.pid" 2>/dev/null || :)
    case "$cli_pid" in ''|*[!0-9]*) :;; *) kill "$cli_pid" 2>/dev/null || :;; esac
    case "$feed_pid" in ''|*[!0-9]*) :;; *) kill "$feed_pid" 2>/dev/null || :;; esac
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
mkdir -m 700 "$T/logs"

cat > "$T/frida" <<'MOCK'
#!/bin/sh
set -eu
if [ "$1" = "--version" ]; then
  echo "Frida mock 17.0.0"
  exit 0
fi
[ "$1" = "-H" ]
[ "$2" = "127.0.0.1:27043" ]
[ "$3" = "-n" ]
[ "$4" = "Gadget" ]
[ "$5" = "-l" ]
[ -f "$6" ] && [ ! -L "$6" ]
[ "$(stat -c %a "$6")" = "600" ]
[ -p /dev/stdin ]
printf 'mock-gadget-session-started\n'
cat >/dev/null
MOCK
chmod 700 "$T/frida"

# This closely mirrors the Java-built Root shell command with host-local paths.
cat > "$T/start.sh" <<'START'
#!/bin/sh
set -eu
umask 077
cli=$1
pkg=com.example.debuggable
port=27043
dir=$2
log="$dir/gadget-$port.log"
script="$dir/gadget-$port.js"
pidfile="$dir/gadget-$port.pid"
pipe="$dir/gadget-$port.stdin"
test -x "$cli" && test ! -L "$cli"
cli_version=$("$cli" --version 2>&1)
pids=$(ps -A -o PID,NAME 2>/dev/null | awk -v pkg="$pkg" 'NR>1 && $1 ~ /^[0-9]+$/ && ($2==pkg || index($2,pkg ":")==1) {print $1}' || :)
if [ -e "$pidfile" ] || [ -e "$pipe" ]; then
  echo "unexpected preexisting session artifacts" >&2
  exit 1
fi
tmp=$(mktemp "$dir/.gadget-$port.XXXXXX")
printf 'send("hello"); console.log("console");\n' > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$script"
chmod 600 "$script"
: >> "$log"
chmod 600 "$log"
mkfifo -m 600 "$pipe"
nohup "$cli" -H "127.0.0.1:$port" -n Gadget -l "$script" < "$pipe" >> "$log" 2>&1 &
cli_pid=$!
nohup tail -f /dev/null > "$pipe" 2>/dev/null < /dev/null &
feed_pid=$!
pid_tmp=$(mktemp "$dir/.gadget-$port.pid.XXXXXX")
printf '%s\n%s\n%s\n%s\n%s\n' "$cli_pid" "$feed_pid" "$cli" "$pkg" "$port" > "$pid_tmp"
chmod 600 "$pid_tmp"
mv -f "$pid_tmp" "$pidfile"
sleep 1
kill -0 "$cli_pid"
kill -0 "$feed_pid"
printf 'FX_GADGET_SESSION_STARTED\ncli_pid=%s\nfeeder_pid=%s\ncli_version=%s\n' "$cli_pid" "$feed_pid" "$cli_version"
START
chmod 700 "$T/start.sh"
"$T/start.sh" "$T/frida" "$T/logs" > "$T/status"
grep -Fq FX_GADGET_SESSION_STARTED "$T/status"
grep -Fq "Frida mock 17.0.0" "$T/status"
[ -p "$T/logs/gadget-27043.stdin" ]
[ "$(stat -c %a "$T/logs/gadget-27043.stdin")" = "600" ]
[ "$(stat -c %a "$T/logs/gadget-27043.js")" = "600" ]
[ "$(stat -c %a "$T/logs/gadget-27043.pid")" = "600" ]
grep -Fq mock-gadget-session-started "$T/logs/gadget-27043.log"
cli_pid=$(sed -n '1p' "$T/logs/gadget-27043.pid")
feed_pid=$(sed -n '2p' "$T/logs/gadget-27043.pid")
[ -n "$cli_pid" ] && [ -n "$feed_pid" ]
kill -0 "$cli_pid"
kill -0 "$feed_pid"

# Stop only the mock processes named by the newly created private session record.
cli_cmd=$(tr '\000' ' ' < "/proc/$cli_pid/cmdline" 2>/dev/null || :)
case "$cli_cmd" in *"$T/frida"*'127.0.0.1:27043'*Gadget*) kill "$cli_pid";; *)
  echo "FAIL: mock CLI process identity was not verifiable" >&2; exit 1;;
esac
feed_cmd=$(tr '\000' ' ' < "/proc/$feed_pid/cmdline" 2>/dev/null || :)
case "$feed_cmd" in *tail*'/dev/null'*) kill "$feed_pid";; *)
  echo "FAIL: mock feeder process identity was not verifiable" >&2; exit 1;;
esac
rm -f "$T/logs/gadget-27043.pid" "$T/logs/gadget-27043.stdin"
sleep 0.1
[ ! -e "$T/logs/gadget-27043.pid" ]
[ ! -e "$T/logs/gadget-27043.stdin" ]
echo "PASS: Frida CLI Gadget session persists beyond launcher, owns FIFO/PID records, logs output, and stops only verified mock processes"
