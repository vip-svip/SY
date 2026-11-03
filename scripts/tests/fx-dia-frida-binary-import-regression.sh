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
    "unique app-private upload temp": 'File.createTempFile(server ? "server-" : "inject-", ".upload", staging)',
    "reject staging symlink": "Files.isSymbolicLink(staging.toPath())",
    "reject source symlink": "Files.isSymbolicLink(source.toPath())",
    "same-directory random Root temp": 'tmp=$(mktemp \\"$d/.fx-frida-import.XXXXXX\\")',
    "Root temp non-symlink validation": '[ -n \\"$tmp\\" ] && [ -f \\"$tmp\\" ] && [ ! -L \\"$tmp\\" ]',
    "Root destination directory symlink rejection": 'test -d \\"$d\\" && test ! -L \\"$d\\"',
    "Root source non-symlink validation": 'test -f \\"$src\\" && test ! -L \\"$src\\"',
    "Root destination symlink rejection": 'if [ -L \\"$dst\\" ]',
    "hash before atomic replace": 'actual=$(sha256sum \\"$tmp\\"',
    "atomic install": 'mv -f \\"$tmp\\" \\"$dst\\"',
    "final destination non-symlink validation": 'test -f \\"$dst\\" && test ! -L \\"$dst\\"',
    "Root temp cleanup trap": 'trap cleanup_tmp 0',
    "source cleanup in finally": "source.delete();",
}
for label, needle in required.items():
    if needle not in source:
        raise SystemExit(f"FAIL: missing {label}: {needle}")
if 'new File(staging, server ? "server.upload" : "inject.upload")' in source:
    raise SystemExit("FAIL: fixed Frida upload staging filenames remain")
if 'tmp=\\"$dst.fx-import.tmp\\"' in source:
    raise SystemExit("FAIL: predictable Root import temp path remains")
print("PASS: Frida binary import source uses unique private staging and random Root temp files")
PY

T=$(mktemp -d "/tmp/fx-dia-frida-binary.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
D="$T/data/fx-frida"
mkdir -p "$D"
SOURCE_A="$T/source-a.bin"
SOURCE_B="$T/source-b.bin"
SENTINEL="$T/unrelated-file"
printf 'FRIDA-BINARY-A\n' > "$SOURCE_A"
printf 'FRIDA-BINARY-B\n' > "$SOURCE_B"
printf 'keep-original-sentinel\n' > "$SENTINEL"

cat > "$T/install.sh" <<'INSTALL'
#!/bin/sh
set -eu
src=$1
dst=$2
d=$(dirname "$dst")
mkdir -p "$d"
test -d "$d" && test ! -L "$d"
test -f "$src" && test ! -L "$src"
if [ -L "$dst" ] || { [ -e "$dst" ] && [ ! -f "$dst" ]; }; then
  echo unsafe-existing-destination >&2
  exit 73
fi
umask 077
tmp=$(mktemp "$d/.fx-frida-import.XXXXXX")
[ -n "$tmp" ] && [ -f "$tmp" ] && [ ! -L "$tmp" ]
cleanup_tmp(){ [ -z "$tmp" ] || rm -f "$tmp"; }
trap cleanup_tmp 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cp "$src" "$tmp"
chmod 0700 "$tmp"
actual=$(sha256sum "$tmp" | awk '{print $1}')
expected=$(sha256sum "$src" | awk '{print $1}')
[ "$actual" = "$expected" ]
mv -f "$tmp" "$dst"
tmp=
test -f "$dst" && test ! -L "$dst"
chmod 0700 "$dst"
actual=$(sha256sum "$dst" | awk '{print $1}')
[ "$actual" = "$expected" ]
INSTALL
chmod 0755 "$T/install.sh"

# An attacker pre-creates the old predictable temp name as a symlink. The new
# same-directory mktemp path must not follow it or modify the target. Two writers
# then race to install the same target; the final file must be one complete input.
ln -s "$SENTINEL" "$D/frida-server.fx-import.tmp"
"$T/install.sh" "$SOURCE_A" "$D/frida-server" & p1=$!
"$T/install.sh" "$SOURCE_B" "$D/frida-server" & p2=$!
wait "$p1"
wait "$p2"
if ! cmp -s "$SOURCE_A" "$D/frida-server" && ! cmp -s "$SOURCE_B" "$D/frida-server"; then
  echo "FAIL: concurrent Frida server imports left a partial/corrupted binary" >&2
  exit 1
fi
"$T/install.sh" "$SOURCE_A" "$D/frida-inject"
[ "$(cat "$SENTINEL")" = "keep-original-sentinel" ] || {
  echo "FAIL: predictable import-temp symlink target was modified" >&2
  exit 1
}
cmp -s "$SOURCE_A" "$D/frida-inject" || { echo "FAIL: Frida inject import content mismatch" >&2; exit 1; }
[ -x "$D/frida-server" ] && [ -x "$D/frida-inject" ] || { echo "FAIL: installed Frida binaries are not executable" >&2; exit 1; }
ln -s "$SENTINEL" "$D/unsafe-destination"
if "$T/install.sh" "$SOURCE_B" "$D/unsafe-destination" 2>/dev/null; then
  echo "FAIL: Root import accepted a symlink destination" >&2
  exit 1
fi
leftovers=$(find "$D" -maxdepth 1 -name '.fx-frida-import.*' -print)
[ -z "$leftovers" ] || { echo "FAIL: random Root import temporary files leaked: $leftovers" >&2; exit 1; }
echo "PASS: concurrent Frida imports use independent temp files and do not follow predictable symlink paths"
