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
    "same-directory random Root temp": ".fx-frida-import.XXXXXX",
    "Root temp non-symlink validation": '[ -n ',
    "Root destination directory symlink rejection": 'test -d ',
    "Root source non-symlink validation": 'test -f ',
    "Root destination symlink rejection": 'unsafe-existing-destination',
    "hash before atomic replace": 'sha256sum ',
    "atomic install": 'mv -f ',
    "final destination non-symlink validation": 'test -f ',
    "Root temp cleanup trap": 'trap cleanup_tmp 0',
    "source cleanup in finally": "source.delete();",
    "per-destination import lock": ".fx-import.lock",
    "atomic private lock acquisition": "set -C; printf",
    "bounded lock wait": "frida-import-lock-timeout",
    "stale lock owner quarantine": '.stale.$$.$lock_wait',
    "lock release on exit": "trap cleanup_import 0",
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

# Leave shell tracing enabled for the local mock section so a failed wait,
# rename, or stale-lock recovery is diagnosable from CI rather than silent under -e.
set -x
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
lock="$dst.fx-import.lock"
lock_held=0
tmp=
cleanup_import(){
  [ -z "$tmp" ] || rm -f "$tmp" 2>/dev/null || :
  if [ "$lock_held" = 1 ]; then
    owner=$(cat "$lock" 2>/dev/null || :)
    if [ "$owner" = "$" ]; then
      release="$lock.release.$"
      if [ ! -e "$release" ] && [ ! -L "$release" ] && mv "$lock" "$release" 2>/dev/null; then
        [ "$(cat "$release" 2>/dev/null || :)" = "$" ] && rm -f "$release" 2>/dev/null || :
      fi
    fi
  fi
}
trap cleanup_import 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
waited=0
while :; do
  if [ ! -L "$lock" ] && [ ! -e "$lock" ]; then
    if (umask 077; set -C; printf '%s\n' "$" > "$lock") 2>/dev/null; then
      lock_held=1
      break
    fi
  fi
  [ ! -L "$lock" ] || exit 74
  owner=$(cat "$lock" 2>/dev/null || :)
  case "$owner" in
    ''|*[!0-9]*) : ;;
    *)
      if ! kill -0 "$owner" 2>/dev/null; then
        owner2=$(cat "$lock" 2>/dev/null || :)
        if [ "$owner2" = "$owner" ] && ! kill -0 "$owner2" 2>/dev/null; then
          stale="$lock.stale.$.$waited"
          if [ ! -e "$stale" ] && [ ! -L "$stale" ] && mv "$lock" "$stale" 2>/dev/null; then
            moved=$(cat "$stale" 2>/dev/null || :)
            if [ "$moved" = "$owner" ] && ! kill -0 "$moved" 2>/dev/null; then
              rm -f "$stale"
            elif [ ! -e "$lock" ] && [ ! -L "$lock" ]; then
              mv "$stale" "$lock" 2>/dev/null || :
            fi
          fi
        fi
      fi
      ;;
  esac
  waited=$((waited+1))
  [ "$waited" -lt 300 ] || exit 75
  sleep 0.01
done
umask 077
tmp=$(mktemp "$d/.fx-frida-import.XXXXXX")
[ -n "$tmp" ] && [ -f "$tmp" ] && [ ! -L "$tmp" ]
cp "$src" "$tmp"
chmod 0700 "$tmp"
sleep 0.2
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
"$T/install.sh" "$SOURCE_A" "$D/frida-server" >"$T/import-a.log" 2>&1 & p1=$!
"$T/install.sh" "$SOURCE_B" "$D/frida-server" >"$T/import-b.log" 2>&1 & p2=$!
wait "$p1" || { rc=$?; echo "FAIL: concurrent Frida server import A exited $rc" >&2; cat "$T/import-a.log" "$T/import-b.log" >&2; ls -la "$D" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; echo "FAIL: concurrent Frida server import B exited $rc" >&2; cat "$T/import-a.log" "$T/import-b.log" >&2; ls -la "$D" >&2; exit "$rc"; }
if ! cmp -s "$SOURCE_A" "$D/frida-server" && ! cmp -s "$SOURCE_B" "$D/frida-server"; then
  echo "FAIL: concurrent Frida server imports left a partial/corrupted binary" >&2
  exit 1
fi
[ ! -e "$D/frida-server.fx-import.lock" ] || { echo "FAIL: per-target import lock leaked" >&2; exit 1; }
"$T/install.sh" "$SOURCE_A" "$D/frida-inject"
[ "$(cat "$SENTINEL")" = "keep-original-sentinel" ] || {
  echo "FAIL: predictable import-temp symlink target was modified" >&2
  exit 1
}
cmp -s "$SOURCE_A" "$D/frida-inject" || { echo "FAIL: Frida inject import content mismatch" >&2; exit 1; }
[ -x "$D/frida-server" ] && [ -x "$D/frida-inject" ] || { echo "FAIL: installed Frida binaries are not executable" >&2; exit 1; }
# A dead owner PID must be quarantined before the next writer proceeds.
printf '99999999\n' > "$D/stale-destination.fx-import.lock"
"$T/install.sh" "$SOURCE_B" "$D/stale-destination"
cmp -s "$SOURCE_B" "$D/stale-destination" || { echo "FAIL: stale-lock recovery import mismatch" >&2; exit 1; }
[ ! -e "$D/stale-destination.fx-import.lock" ] || { echo "FAIL: stale per-target import lock was not removed" >&2; exit 1; }
ln -s "$SENTINEL" "$D/unsafe-destination"
if "$T/install.sh" "$SOURCE_B" "$D/unsafe-destination" 2>/dev/null; then
  echo "FAIL: Root import accepted a symlink destination" >&2
  exit 1
fi
leftovers=$(find "$D" -maxdepth 1 -name '.fx-frida-import.*' -print)
[ -z "$leftovers" ] || { echo "FAIL: random Root import temporary files leaked: $leftovers" >&2; exit 1; }
echo "PASS: concurrent Frida imports use independent temp files and do not follow predictable symlink paths"
