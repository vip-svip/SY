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

print("Installed POSIX noclobber subscription cache lock.")
