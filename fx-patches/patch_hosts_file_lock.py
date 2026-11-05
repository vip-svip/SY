#!/usr/bin/env python3
"""Replace the restored Hosts cache mkdir lock with a POSIX noclobber file lock."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
target = module / "scripts/apply.sh"
if not target.is_file():
    raise SystemExit(f"restored FX Hosts apply source missing: {target}")

source = target.read_text(encoding="utf-8")
marker = "# FX_HOSTS_FILE_LOCK_V3"
required_lock_tokens = (
    '_hf_release="$_hf_lock.release.$"',
    'mv "$_hf_lock" "$_hf_release"',
    'if [ "$_hf_release_owner" = "$" ]; then',
    '_hf_stale="$_hf_lock.stale.$.$_hf_wait"',
    'mv "$_hf_lock" "$_hf_stale"',
    'if [ "$_hf_moved_owner" = "$_hf_owner" ]',
)
if marker in source and all(token in source for token in required_lock_tokens):
    print("Hosts cache already uses the complete POSIX atomic file lock.")
    raise SystemExit(0)
if marker in source:
    print("Existing V3 Hosts lock is incomplete; repairing the entire lock block.")

start_token = '  _hf_lock="$PG/cache/rules/.lock.$_hf_key"\n'
end_token = "  # Keep a verified previous generation."
start = source.find(start_token)
end = source.find(end_token, start + len(start_token)) if start >= 0 else -1
if start < 0 or end < 0:
    raise SystemExit("Hosts cache lock block anchors missing; refusing a partial rewrite")

new_block = r'''  # FX_HOSTS_FILE_LOCK_V3
  # noclobber redirection provides portable exclusive file creation. The reader
  # also accepts legacy PID-bearing directories during module upgrades.
  _hf_lock="$PG/cache/rules/.lock.$_hf_key"
  _hf_lock_held=0

  _hf_read_lock_owner() {
    _hf_path=$1
    [ ! -L "$_hf_path" ] || return 1
    if [ -d "$_hf_path" ]; then
      # A legacy directory lock is trusted only when its owner record is a
      # regular file. Never cat a FIFO, socket, device or symlink here.
      [ ! -L "$_hf_path/pid" ] && [ -f "$_hf_path/pid" ] || return 1
      cat "$_hf_path/pid" 2>/dev/null
    elif [ -f "$_hf_path" ]; then
      cat "$_hf_path" 2>/dev/null
    else
      return 1
    fi
  }

  _hf_remove_lock_path() {
    _hf_path=$1
    [ ! -L "$_hf_path" ] || return 1
    if [ -d "$_hf_path" ]; then
      # Retire only an empty directory or one containing exactly a regular,
      # non-symlink PID file. Unknown entries are user data, not lock debris.
      _hf_found_pid=0
      for _hf_entry in "$_hf_path"/* "$_hf_path"/.[!.]* "$_hf_path"/..?*; do
        [ -e "$_hf_entry" ] || [ -L "$_hf_entry" ] || continue
        [ "$_hf_entry" = "$_hf_path/pid" ] || return 1
        [ ! -L "$_hf_entry" ] && [ -f "$_hf_entry" ] || return 1
        _hf_found_pid=1
      done
      if [ "$_hf_found_pid" = 1 ]; then
        [ ! -L "$_hf_path/pid" ] && [ -f "$_hf_path/pid" ] || return 1
        rm -f "$_hf_path/pid" 2>/dev/null || return 1
      fi
      rmdir "$_hf_path" 2>/dev/null
    elif [ -f "$_hf_path" ]; then
      rm -f "$_hf_path" 2>/dev/null
    else
      return 1
    fi
  }

  _hf_unlock() {
    [ "$_hf_lock_held" = 1 ] || return 0
    _hf_owner=$(_hf_read_lock_owner "$_hf_lock" 2>/dev/null || :)
    if [ "$_hf_owner" = "$$" ]; then
      _hf_release="$_hf_lock.release.$$"
      _hf_release_try=0
      while { [ -e "$_hf_release" ] || [ -L "$_hf_release" ]; } && [ "$_hf_release_try" -lt 20 ]; do
        _hf_release_try=$((_hf_release_try+1))
        _hf_release="$_hf_lock.release.$$.$_hf_release_try"
      done
      if [ ! -e "$_hf_release" ] && [ ! -L "$_hf_release" ] &&
         mv "$_hf_lock" "$_hf_release" 2>/dev/null; then
        _hf_release_owner=$(_hf_read_lock_owner "$_hf_release" 2>/dev/null || :)
        if [ "$_hf_release_owner" = "$$" ]; then
          _hf_remove_lock_path "$_hf_release" || :
        fi
      fi
    fi
    _hf_lock_held=0
    return 0
  }

  _hf_wait=0
  while :; do
    if [ ! -L "$_hf_lock" ] && [ ! -e "$_hf_lock" ]; then
      if ( umask 077; set -C; printf '%s\n' "$$" > "$_hf_lock" ) 2>/dev/null; then
        _hf_lock_held=1
        break
      fi
    fi

    _hf_owner=$(_hf_read_lock_owner "$_hf_lock" 2>/dev/null || :)
    case "$_hf_owner" in
      ''|*[!0-9]*) : ;;
      *)
        if ! kill -0 "$_hf_owner" 2>/dev/null; then
          _hf_owner2=$(_hf_read_lock_owner "$_hf_lock" 2>/dev/null || :)
          if [ "$_hf_owner2" = "$_hf_owner" ] && ! kill -0 "$_hf_owner2" 2>/dev/null; then
            _hf_stale="$_hf_lock.stale.$$.$_hf_wait"
            if [ ! -e "$_hf_stale" ] && [ ! -L "$_hf_stale" ] &&
               mv "$_hf_lock" "$_hf_stale" 2>/dev/null; then
              _hf_moved_owner=$(_hf_read_lock_owner "$_hf_stale" 2>/dev/null || :)
              if [ "$_hf_moved_owner" = "$_hf_owner" ] &&
                 ! kill -0 "$_hf_moved_owner" 2>/dev/null; then
                _hf_remove_lock_path "$_hf_stale" || :
              elif [ ! -e "$_hf_lock" ] && [ ! -L "$_hf_lock" ]; then
                # The owner changed between the recheck and rename; restore the
                # moved path instead of deleting a possibly live lock.
                mv "$_hf_stale" "$_hf_lock" 2>/dev/null || :
              fi
            fi
          fi
        fi
        ;;
    esac

    _hf_wait=$((_hf_wait+1))
    if [ "$_hf_wait" -ge 200 ]; then
      pg_log "hosts: cache lock busy; refusing concurrent cache write for [subscription URL redacted]"
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done

'''
updated = source[:start] + new_block + source[end:]
target.write_text(updated, encoding="utf-8")
target.chmod(0o755)
print("Installed POSIX noclobber Hosts cache lock.")
