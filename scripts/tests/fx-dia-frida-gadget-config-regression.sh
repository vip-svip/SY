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
    "random same-directory temp file": r'tmp=$(mktemp \"$dir/.fx-dia-frida-config.XXXXXX\")',
    "temp file checked as regular non-symlink": r'[ -n \"$tmp\" ] && [ -f \"$tmp\" ] && [ ! -L \"$tmp\" ]',
    "directory symlink rejection": r'test -d \"$dir\" && test ! -L \"$dir\"',
    "temporary cleanup trap": r'trap cleanup_tmp 0',
    "signal exit traps": r"trap 'exit 129' HUP",
    "private temporary file mode before creation": r'umask 077; mkdir -p \"$dir\"',
    "decode failure cleanup": r'if ! printf ',
    "non-empty decoded configuration": r'test -s \"$tmp\"',
    "chmod failure cleanup": r'if ! chmod 0644 \"$tmp\"',
    "atomic replace failure cleanup": r'if ! mv -f \"$tmp\" \"$config\"',
    "atomic destination replace": r'mv -f \"$tmp\" \"$config\"',
    "clear moved temp before exit trap": r'tmp=; test -f \"$config\"',
    "Gadget loopback-only listener": 'interaction.put("address", "127.0.0.1")',
    "Gadget port conflict policy": 'interaction.put("on_port_conflict", "fail")',
    "Gadget WAIT/RESUME mode": 'interaction.put("on_load", wait ? "wait" : "resume")',
    "Gadget default avoids frida-server port": 'getString("gadget_port", "27043")',
    "Gadget input hint avoids frida-server port": 'gadgetPort.setHint("27043")',
    "Gadget rejects frida-server port": 'if (port == 27042)',
    "Gadget connection command defaults to separate port": 'gadgetPort == null ? "27043"',
    "ADB forwarding command": 'adb forward tcp:',
    "local Gadget connection target": 'frida-ps -H 127.0.0.1:',
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing {label}: {needle}")
if 'tmp=\"$config.tmp.$$\"' in source:
    raise SystemExit("FAIL: Gadget temporary filename still uses predictable PID suffix")
print("PASS: Gadget writer uses random private same-directory temp files and atomic replacement")
PY

T=$(mktemp -d "/tmp/fx-dia-gadget-write.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
CONFIG="$T/gadget.config.so"
SENTINEL="$T/symlink-sentinel"
printf 'keep-original-sentinel\n' > "$SENTINEL"
cat > "$T/writer.sh" <<'WRITER'
#!/bin/sh
set -eu
CONFIG=$1
LABEL=$2
READY=$3
RELEASE=$4
SENTINEL=$5
dir=$(dirname "$CONFIG")
umask 077
mkdir -p "$dir"
[ -d "$dir" ] && [ ! -L "$dir" ]
# Model an attacker pre-creating the old predictable PID-based temp path.
legacy_tmp="$CONFIG.tmp.$$"
ln -s "$SENTINEL" "$legacy_tmp"
tmp=$(mktemp "$dir/.fx-dia-frida-config.XXXXXX")
[ -n "$tmp" ] && [ -f "$tmp" ] && [ ! -L "$tmp" ]
cleanup_tmp(){ [ -z "$tmp" ] || rm -f "$tmp"; }
trap cleanup_tmp 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf '{"label":"%s","address":"127.0.0.1","interaction":{"type":"listen","on_load":"wait"}}\n' "$LABEL" > "$tmp"
test -s "$tmp"
chmod 0644 "$tmp"
: > "$READY"
tries=0
while [ ! -e "$RELEASE" ]; do
  tries=$((tries+1))
  [ "$tries" -lt 400 ] || exit 70
  sleep 0.01
done
mv -f "$tmp" "$CONFIG"
tmp=
WRITER
chmod 0755 "$T/writer.sh"

# Two independent writers must not collide, and neither may follow a pre-planted
# legacy PID temp symlink to overwrite an unrelated file.
sh "$T/writer.sh" "$CONFIG" first "$T/ready.first" "$T/release.first" "$SENTINEL" &
p1=$!
sh "$T/writer.sh" "$CONFIG" second "$T/ready.second" "$T/release.second" "$SENTINEL" &
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
[ "$(cat "$SENTINEL")" = "keep-original-sentinel" ] || {
  echo "FAIL: a pre-existing predictable temp symlink was followed and its target modified" >&2
  cat "$SENTINEL" >&2 || :
  exit 1
}
leftovers=$(find "$T" -maxdepth 1 -name '.fx-dia-frida-config.*' -print)
[ -z "$leftovers" ] || {
  echo "FAIL: random Gadget config temporary file leaked: $leftovers" >&2
  exit 1
}
echo "PASS: concurrent Frida Gadget config writes use random private temp files and do not follow legacy symlinks"
