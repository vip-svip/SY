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
    "Gadget message/console log action is reachable from the UI":
        'button("查看 Gadget 消息/控制台日志", () -> showGadgetSessionLog())',
    "Frida Gadget control endpoint is loopback-only":
        '"127.0.0.1:$port"',
    "Frida inject connects to the Gadget process by name":
        '-n Gadget -s \\"$tmp\\"',
    "remote endpoint uses selected Gadget port":
        '-H \\"127.0.0.1:$port\\"',
    "remote attach is performed by the configured local frida-inject binary":
        'injector = currentInjectorPath()',
    "target is revalidated as debuggable before remote control":
        'targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE',
    "system packages are excluded":
        'targetInfo.flags & ApplicationInfo.FLAG_SYSTEM',
    "target package processes must currently be running":
        'FX_GADGET_TARGET_NOT_RUNNING',
    "target process enumeration matches target package":
        'index($2,pkg \\":\\")==1',
    "Frida script size is bounded":
        'sourceBytes.length > 48 * 1024',
    "Frida script rejects NUL":
        'source.indexOf(0) >= 0',
    "script is staged using unpredictable same-directory temp":
        'mktemp \\"$dir/.gadget-$port.XXXXXX\\"',
    "Root shell defaults to private file permissions":
        'umask 077',
    "temporary script is restricted to owner":
        'chmod 600 \\"$tmp\\"',
    "temporary script is removed by exit trap":
        'trap cleanup_tmp 0',
    "Gadget log directory is restricted":
        'chmod 700 \\"$dir\\"',
    "Gadget log file is restricted":
        'chmod 600 \\"$log\\"',
    "existing log symlink is rejected":
        '[ ! -L \\"$log\\" ]',
    "Gadget CLI output is captured in per-port log":
        '>> \\"$log\\" 2>&1',
    "log viewer only reads bounded tail":
        'tail -n 500',
    "Gadget config preserves WAIT/RESUME semantics":
        'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget config rejects frida-server port":
        'if (port == 27042)',
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: {label}: missing {needle!r}")

attach = source[source.index("private void attachToGadgetAndResume()"):
                 source.index("private void showGadgetSessionLog()")]
if "0.0.0.0" in attach:
    raise SystemExit("FAIL: remote Gadget attach must not bind to all interfaces")
if 'Runtime.exec' in attach or 'sh -c' in attach:
    raise SystemExit("FAIL: Frida attach must use the bounded RootAccess command bridge")
if "FLAG_DEBUGGABLE" not in attach or "FLAG_SYSTEM" not in attach:
    raise SystemExit("FAIL: target eligibility checks were removed from the attach action")
print("PASS: Dia Frida Gadget attach validates target/port, stages a private script, captures CLI output, and provides a bounded session-log view")
PY

# Exercise the remote CLI contract with a local mock. This does not claim
# device-side Frida compatibility; it guards argument ordering and temp cleanup.
T=$(mktemp -d "/tmp/fx-dia-gadget-session.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
mkdir -m 700 "$T/logs"
cat > "$T/frida-inject" <<'MOCK'
#!/bin/sh
set -eu
[ "$1" = "-H" ]
[ "$2" = "127.0.0.1:27043" ]
[ "$3" = "-n" ]
[ "$4" = "Gadget" ]
[ "$5" = "-s" ]
[ -f "$6" ] && [ ! -L "$6" ]
[ "$(stat -c %a "$6")" = "600" ]
printf 'mock-send-message\nmock-console-log\n'
MOCK
chmod 700 "$T/frida-inject"
cat > "$T/run-attach.sh" <<'RUN'
#!/bin/sh
set -eu
umask 077
injector=$1
log=$2
dir=$3
encoded=$4
port=27043
tmp=$(mktemp "$dir/.gadget-$port.XXXXXX")
[ -f "$tmp" ] && [ ! -L "$tmp" ]
cleanup_tmp(){ [ -z "$tmp" ] || rm -f "$tmp"; }
trap cleanup_tmp 0
printf '%s' "$encoded" | base64 -d > "$tmp"
chmod 600 "$tmp"
if "$injector" -H "127.0.0.1:$port" -n Gadget -s "$tmp" >> "$log" 2>&1; then
  echo FX_GADGET_ATTACHED_AND_WAIT_RELEASED
else
  rc=$?
  exit "$rc"
fi
RUN
chmod 700 "$T/run-attach.sh"
ENCODED=$(printf 'send("message"); console.log("console");\n' | base64 | tr -d '\n')
"$T/run-attach.sh" "$T/frida-inject" "$T/logs/gadget-27043.log" "$T/logs" "$ENCODED" > "$T/status"
grep -Fq FX_GADGET_ATTACHED_AND_WAIT_RELEASED "$T/status"
grep -Fq mock-send-message "$T/logs/gadget-27043.log"
grep -Fq mock-console-log "$T/logs/gadget-27043.log"
[ -z "$(find "$T/logs" -maxdepth 1 -name '.gadget-27043.*' -print -quit)" ] || {
  echo "FAIL: temporary Gadget script leaked after attach" >&2
  exit 1
}
echo "PASS: Gadget CLI mock receives loopback endpoint/name/script and writes session output without leaking temp script"
