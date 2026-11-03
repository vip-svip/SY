#!/usr/bin/env python3
"""Replace the flaky subscription mkdir lock with a POSIX noclobber file lock."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
target = module / "scripts/subfetch.sh"
if not target.is_file():
    raise SystemExit(f"restored FX subfetch source missing: {target}")

source = target.read_text(encoding="utf-8")
marker = "# FX_SUBFETCH_FILE_LOCK_V2"
if marker in source:
    print("Subscription cache already uses the POSIX atomic file lock.")
    raise SystemExit(0)

start_token = 'LOCK="$SUBDIR/.lock.$_key"\n'
end_token = '# 只有显式 --local 才允许「没缓存就报错」'
start = source.find(start_token)
end = source.find(end_token, start + len(start_token)) if start >= 0 else -1
if start < 0 or end < 0:
    raise SystemExit("subfetch lock block anchors not found; refusing a partial rewrite")

new_block = r'''# FX_SUBFETCH_FILE_LOCK_V2
# Use noclobber redirection as the portable O_CREAT|O_EXCL primitive. This
# avoids the observed mkdir-lock race on restored module filesystems.
LOCK="$SUBDIR/.lock.$_key"
LOCK_HELD=0

_sl_read_lock_owner() {
  _sl_path=$1
  [ ! -L "$_sl_path" ] || return 1
  if [ -d "$_sl_path" ]; then
    [ ! -L "$_sl_path/pid" ] || return 1
    cat "$_sl_path/pid" 2>/dev/null
  elif [ -f "$_sl_path" ]; then
    cat "$_sl_path" 2>/dev/null
  else
    return 1
  fi
}

_sl_remove_owned_lock_path() {
  _sl_path=$1
  [ ! -L "$_sl_path" ] || return 1
  if [ -d "$_sl_path" ]; then
    rm -rf "$_sl_path" 2>/dev/null
  elif [ -f "$_sl_path" ]; then
    rm -f "$_sl_path" 2>/dev/null
  else
    return 1
  fi
}

subfetch_unlock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  _sl_owner=$(_sl_read_lock_owner "$LOCK" 2>/dev/null || :)
  if [ "$_sl_owner" = "$$" ]; then
    _sl_release="$LOCK.release.$$"
    _sl_release_try=0
    while { [ -e "$_sl_release" ] || [ -L "$_sl_release" ]; } && [ "$_sl_release_try" -lt 20 ]; do
      _sl_release_try=$((_sl_release_try+1))
      _sl_release="$LOCK.release.$$.$_sl_release_try"
    done
    if [ ! -e "$_sl_release" ] && [ ! -L "$_sl_release" ] &&
       mv "$LOCK" "$_sl_release" 2>/dev/null; then
      _sl_release_owner=$(_sl_read_lock_owner "$_sl_release" 2>/dev/null || :)
      if [ "$_sl_release_owner" = "$$" ]; then
        _sl_remove_owned_lock_path "$_sl_release" || :
      fi
    fi
  fi
  LOCK_HELD=0
  return 0
}
trap 'subfetch_unlock' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

_sl_try=0
while :; do
  # Never follow or replace a symlink at the canonical lock path.
  if [ ! -L "$LOCK" ] && [ ! -e "$LOCK" ]; then
    if ( umask 077; set -C; printf '%s\n' "$$" > "$LOCK" ) 2>/dev/null; then
      LOCK_HELD=1
      break
    fi
  fi

  _sl_owner=$(_sl_read_lock_owner "$LOCK" 2>/dev/null || :)
  case "$_sl_owner" in
    ''|*[!0-9]*) ;;
    *)
      if ! kill -0 "$_sl_owner" 2>/dev/null; then
        # Recheck and quarantine only the exact dead owner we observed. Legacy
        # directory locks are accepted during upgrade; new locks are regular
        # private files created atomically with noclobber.
        _sl_again=$(_sl_read_lock_owner "$LOCK" 2>/dev/null || :)
        if [ "$_sl_again" = "$_sl_owner" ]; then
          _sl_stale="$LOCK.stale.$$.$_sl_try"
          if [ ! -e "$_sl_stale" ] && [ ! -L "$_sl_stale" ] &&
             mv "$LOCK" "$_sl_stale" 2>/dev/null; then
            _sl_moved_owner=$(_sl_read_lock_owner "$_sl_stale" 2>/dev/null || :)
            if [ "$_sl_moved_owner" = "$_sl_owner" ] &&
               ! kill -0 "$_sl_moved_owner" 2>/dev/null; then
              _sl_remove_owned_lock_path "$_sl_stale" || :
            fi
          fi
        fi
      fi
      ;;
  esac

  _sl_try=$((_sl_try+1))
  if [ "$_sl_try" -ge 300 ]; then
    printf '{"ok":0,"err":"subscription cache busy for 30 seconds; retry later","key":"%s"}\n' "$_key"
    exit 0
  fi
  sleep 0.1
done

'''
updated = source[:start] + new_block + source[end:]
target.write_text(updated, encoding="utf-8")
target.chmod(0o755)

# Keep legacy tests aligned with the v2 file lock while still covering upgrade
# from both old PID-bearing directory locks and stale file locks.
test_root = module / "scripts/tests"
ownership_test = test_root / "v1.0.0-subfetch-stale-lock-ownership-regression.sh"
reclaim_test = test_root / "v1.0.0-subfetch-stale-lock-reclaim-regression.sh"

def stale_lock_test_source(label: str) -> str:
    return r'''#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
F="$ROOT/scripts/subfetch.sh"
fail(){ echo "FAIL: ''' + label + r''': $*" >&2; exit 1; }
[ -s "$F" ] || fail "subfetch source missing"
grep -Fq 'FX_SUBFETCH_FILE_LOCK_V2' "$F" || fail "v2 file-lock marker missing"
grep -Fq '_sl_stale="$LOCK.stale.' "$F" || fail "stale quarantine path must be unique per reaper"
grep -Fq '$_sl_try"' "$F" || fail "stale quarantine path must include a per-attempt suffix"
grep -Fq 'mv "$LOCK" "$_sl_stale"' "$F" || fail "lock must be quarantined by atomic rename"
grep -Fq '_sl_moved_owner=$(_sl_read_lock_owner "$_sl_stale"' "$F" || fail "quarantined owner must be re-read"
grep -Fq '[ "$_sl_moved_owner" = "$_sl_owner" ]' "$F" || fail "quarantined owner must match the observed owner"
if grep -Fq 'mv "$_sl_stale" "$LOCK"' "$F"; then fail "unverified quarantine must not be restored into a replacement lock"; fi
if grep -Eq 'rm -f "\$LOCK/pid"|rmdir "\$LOCK"' "$F"; then fail "stale reaper must not unlink a pid and directory separately"; fi
sh -n "$F" || fail "subfetch shell syntax invalid"

run_stale_case() {
  kind=$1
  T=$(mktemp -d "\${TMPDIR:-/tmp}/fx-subfetch-stale-$kind.XXXXXX")
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  mkdir -p "$T/state/subs" "$T/bin"
  url="https://example.invalid/stale-$kind"
  key=$(printf '%s' "$url" | cksum | awk '{print $1}')
  lock="$T/state/subs/.lock.$key"
  if [ "$kind" = directory ]; then
    mkdir "$lock"
    printf '99999999\n' > "$lock/pid"
  else
    printf '99999999\n' > "$lock"
  fi
  printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
  cat >> "$T/bin/curl" <<'CURL'
#!/bin/sh
out=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '-o' ]; then shift; out=$1; fi
  shift
done
[ -n "$out" ] || exit 64
body='vless://123e4567-e89b-12d3-a456-426614174000@edge.example:443?encryption=none#test'
if [ "$out" = '-' ]; then printf '%s\n' "$body"; else printf '%s\n' "$body" > "$out"; fi
CURL
  chmod 0755 "$T/bin/curl"
  printf '#!%s\n' "$(command -v sh)" > "$T/bin/timeout"
  cat >> "$T/bin/timeout" <<'TIMEOUT'
#!/bin/sh
shift
exec "$@"
TIMEOUT
  chmod 0755 "$T/bin/timeout"
  PATH="$T/bin:$PATH" PG="$T/state" MODDIR="$ROOT" sh "$F" "$url" --force > "$T/out" || fail "$kind stale lock request exited non-zero"
  grep -Fq '"ok":1' "$T/out" || { cat "$T/out" >&2; fail "$kind stale lock was not reclaimed"; }
  [ -s "$T/state/subs/$key.txt" ] || fail "$kind stale lock did not produce cache body"
  [ -s "$T/state/subs/$key.meta" ] || fail "$kind stale lock did not produce cache metadata"
  [ ! -e "$lock" ] && [ ! -L "$lock" ] || fail "$kind stale lock path remains after successful fetch"
  rm -rf "$T"
  trap - EXIT HUP INT TERM
}
run_stale_case directory
run_stale_case file
echo 'PASS: stale subscription directory and file locks are reclaimed after owner verification'
'''
if test_root.is_dir():
    ownership_test.write_text(stale_lock_test_source("ownership"), encoding="utf-8")
    reclaim_test.write_text(stale_lock_test_source("reclaim"), encoding="utf-8")
    ownership_test.chmod(0o755)
    reclaim_test.chmod(0o755)

print("Installed POSIX noclobber subscription cache lock and refreshed stale-lock regressions.")
