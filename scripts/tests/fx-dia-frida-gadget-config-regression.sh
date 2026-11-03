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
    "PID-unique temporary name": r'tmp=\"$config.tmp.$$\"',
    "temporary cleanup trap": r'trap cleanup_tmp 0',
    "signal exit traps": r"trap 'exit 129' HUP",
    "private temporary file mode": r"umask 077",
    "decode failure cleanup": r'if ! printf ',
    "chmod failure cleanup": r'if ! chmod 0644 \"$tmp\"',
    "atomic replace failure cleanup": r'if ! mv -f \"$tmp\" \"$config\"',
    "atomic destination replace": r'mv -f \"$tmp\" \"$config\"',
    "Gadget loopback-only listener": 'interaction.put("address", "127.0.0.1")',
    "Gadget port conflict policy": 'interaction.put("on_port_conflict", "fail")',
    "Gadget WAIT/RESUME mode": 'interaction.put("on_load", wait ? "wait" : "resume")',
    "ADB forwarding command": 'adb forward tcp:',
    "local Gadget connection target": 'frida-ps -H 127.0.0.1:',
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing {label}: {needle}")
if r'tmp=\"$config.tmp.$\"' in source:
    raise SystemExit("FAIL: Gadget temporary filename still uses a shared literal dollar suffix")
print("PASS: Frida Gadget writer uses unique temp files, cleanup traps, loopback and atomic replacement")
PY

T=$(mktemp -d "/tmp/fx-dia-gadget-write.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
CONFIG="$T/gadget.config.so"
cat > "$T/writer.sh" <<'WRITER'
#!/bin/sh
set -eu
CONFIG=$1
LABEL=$2
READY=$3
RELEASE=$4
tmp="$CONFIG.tmp.$$"
cleanup_tmp(){ [ -z "$tmp" ] || rm -f "$tmp"; }
trap cleanup_tmp 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
printf '{"label":"%s","address":"127.0.0.1"}\n' "$LABEL" > "$tmp"
chmod 0644 "$tmp"
: > "$READY"
tries=0
while [ ! -e "$RELEASE" ]; do
  tries=$((tries+1))
  [ "$tries" -lt 400 ] || exit 70
  sleep 0.01
done
mv -f "$tmp" "$CONFIG"
WRITER
chmod 0755 "$T/writer.sh"

# Two independent shell processes stage two configurations to the same target.
# Releasing them in a known order proves their temporary paths do not collide.
sh "$T/writer.sh" "$CONFIG" first "$T/ready.first" "$T/release.first" &
p1=$!
sh "$T/writer.sh" "$CONFIG" second "$T/ready.second" "$T/release.second" &
p2=$!

tries=0
while { [ ! -e "$T/ready.first" ] || [ ! -e "$T/ready.second" ]; } && [ "$tries" -lt 400 ]; do
  tries=$((tries+1))
  sleep 0.01
done
[ -e "$T/ready.first" ] && [ -e "$T/ready.second" ] || {
  echo "FAIL: both Gadget config writers did not stage temporary files" >&2
  exit 1
}

touch "$T/release.first"
wait "$p1" || { echo "FAIL: first Gadget config writer failed" >&2; exit 1; }
touch "$T/release.second"
wait "$p2" || { echo "FAIL: second Gadget config writer failed after first atomic replace" >&2; exit 1; }

grep -Fq '"label":"second"' "$CONFIG" || {
  echo "FAIL: final Gadget config is incomplete or out of replacement order" >&2
  cat "$CONFIG" >&2 || :
  exit 1
}
grep -Fq '"address":"127.0.0.1"' "$CONFIG" || {
  echo "FAIL: final Gadget config is missing loopback address" >&2
  exit 1
}
leftovers=$(find "$T" -maxdepth 1 -name 'gadget.config.so.tmp.*' -print)
[ -z "$leftovers" ] || {
  echo "FAIL: Gadget config temporary file leaked: $leftovers" >&2
  exit 1
}
echo "PASS: concurrent Frida Gadget config writes use separate PID temp files and atomic replace"
