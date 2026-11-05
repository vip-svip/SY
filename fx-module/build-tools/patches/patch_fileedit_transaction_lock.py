#!/usr/bin/env python3
from pathlib import Path
import sys
MARKER = "# FX_FILEEDIT_TRANSACTION_LOCK_V1"
LOCK_BLOCK = r'''# FX_FILEEDIT_TRANSACTION_LOCK_V1
# Serialize read-modify-write editor operations per logical source.
FE_LOCK_HELD=0
FE_LOCK_PATH=""
FE_LOCK_PID=""
fe_lock_owner() {
  [ ! -L "$1" ] && [ -f "$1" ] || return 1
  sed -n '1p' "$1" 2>/dev/null | tr -d ' \r'
}
fe_lock_release() {
  [ "$FE_LOCK_HELD" = 1 ] || return 0
  _fe_owner=$(fe_lock_owner "$FE_LOCK_PATH" 2>/dev/null || :)
  [ "$_fe_owner" != "$FE_LOCK_PID" ] || rm -f "$FE_LOCK_PATH" 2>/dev/null || :
  FE_LOCK_HELD=0
}
fe_lock_acquire() {
  _fe_rest=""
  IFS=' ' read -r FE_LOCK_PID _fe_rest < /proc/self/stat || {
    echo '{"ok":0,"err":"cannot determine editor lock owner"}'; return 1;
  }
  case "$FE_LOCK_PID" in ''|0|*[!0-9]*) echo '{"ok":0,"err":"invalid lock owner"}'; return 1 ;; esac
  [ -d "$PG" ] && [ ! -L "$PG" ] || { echo '{"ok":0,"err":"unsafe state directory"}'; return 1; }
  _fe_root="$PG/fileedit-locks"
  if [ -e "$_fe_root" ] || [ -L "$_fe_root" ]; then
    [ -d "$_fe_root" ] && [ ! -L "$_fe_root" ] || { echo '{"ok":0,"err":"unsafe lock directory"}'; return 1; }
  else
    mkdir -m 700 "$_fe_root" 2>/dev/null || {
      [ -d "$_fe_root" ] && [ ! -L "$_fe_root" ] || { echo '{"ok":0,"err":"cannot create lock directory"}'; return 1; }
    }
  fi
  chmod 700 "$_fe_root" 2>/dev/null || { echo '{"ok":0,"err":"cannot secure lock directory"}'; return 1; }
  case "$spec" in
    hosts) _fe_key=hosts ;;
    builtin:*|fx:*)
      _fe_digest=$(printf '%s' "$spec" | sha256sum 2>/dev/null) || { echo '{"ok":0,"err":"cannot identify editor source"}'; return 1; }
      _fe_key="source-${_fe_digest%% *}"
      ;;
    *) echo '{"ok":0,"err":"source is not writable"}'; return 1 ;;
  esac
  FE_LOCK_PATH="$_fe_root/$_fe_key.lock"
  [ ! -L "$FE_LOCK_PATH" ] || { echo '{"ok":0,"err":"editor lock path is a symbolic link"}'; return 1; }
  _fe_tmp=$(mktemp "$_fe_root/.owner.XXXXXX") || { echo '{"ok":0,"err":"cannot stage lock owner"}'; return 1; }
  (umask 077; printf '%s\n' "$FE_LOCK_PID" > "$_fe_tmp") || { rm -f "$_fe_tmp"; echo '{"ok":0,"err":"cannot write lock owner"}'; return 1; }
  chmod 600 "$_fe_tmp" || { rm -f "$_fe_tmp"; echo '{"ok":0,"err":"cannot secure lock owner"}'; return 1; }
  _fe_tries=0
  _fe_retries=${FX_FILEEDIT_LOCK_RETRIES:-20}
  case "$_fe_retries" in ''|*[!0-9]*|0) _fe_retries=20 ;; esac
  [ "$_fe_retries" -le 120 ] 2>/dev/null || _fe_retries=120
  trap 'fe_lock_release' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  while :; do
    if [ -L "$FE_LOCK_PATH" ]; then
      rm -f "$_fe_tmp"; echo '{"ok":0,"err":"editor lock path is a symbolic link"}'; return 1
    fi
    if [ ! -e "$FE_LOCK_PATH" ]; then
      FE_LOCK_HELD=1
      if ln "$_fe_tmp" "$FE_LOCK_PATH" 2>/dev/null; then
        rm -f "$_fe_tmp" 2>/dev/null || :
        return 0
      fi
      FE_LOCK_HELD=0
    else
      _fe_owner=$(fe_lock_owner "$FE_LOCK_PATH" 2>/dev/null || :)
      case "$_fe_owner" in
        ''|0|*[!0-9]*) : ;;
        *)
          if ! kill -0 "$_fe_owner" 2>/dev/null; then
            _fe_owner2=$(fe_lock_owner "$FE_LOCK_PATH" 2>/dev/null || :)
            if [ "$_fe_owner2" = "$_fe_owner" ] && ! kill -0 "$_fe_owner2" 2>/dev/null; then
              _fe_stale="$FE_LOCK_PATH.stale.$FE_LOCK_PID.$_fe_tries"
              if [ ! -e "$_fe_stale" ] && [ ! -L "$_fe_stale" ] && mv "$FE_LOCK_PATH" "$_fe_stale" 2>/dev/null; then
                _fe_moved=$(fe_lock_owner "$_fe_stale" 2>/dev/null || :)
                if [ "$_fe_moved" = "$_fe_owner" ] && ! kill -0 "$_fe_moved" 2>/dev/null; then
                  rm -f "$_fe_stale" 2>/dev/null || :
                elif [ ! -e "$FE_LOCK_PATH" ] && [ ! -L "$FE_LOCK_PATH" ]; then
                  mv "$_fe_stale" "$FE_LOCK_PATH" 2>/dev/null || :
                fi
              fi
              continue
            fi
          fi
          ;;
      esac
    fi
    _fe_tries=$((_fe_tries + 1))
    if [ "$_fe_tries" -ge "$_fe_retries" ]; then
      rm -f "$_fe_tmp" 2>/dev/null || :
      echo '{"ok":0,"err":"editor source is busy; retry after the current save finishes"}'
      return 1
    fi
    sleep 1
  done
}
'''
CALL_BLOCK = r'''# Lock the complete read-modify-write transaction, not only the final rename.
case "$op" in
  edit|ins|del|put|replacepage|reset|import-external)
    fe_lock_acquire || exit 0
    ;;
esac

'''
def main():
    if len(sys.argv) != 2:
        print("usage: patch_fileedit_transaction_lock.py MODULE_ROOT", file=sys.stderr)
        return 2
    target = Path(sys.argv[1]) / "scripts/fileedit.sh"
    if not target.is_file():
        print(f"fileedit source missing: {target}", file=sys.stderr)
        return 1
    source = target.read_text(encoding="utf-8")
    if MARKER in source:
        if "fe_lock_acquire || exit 0" not in source:
            print("fileedit lock marker exists but dispatch hook is missing", file=sys.stderr)
            return 1
        print("File editor transaction lock already applied.")
        return 0
    host_init_end = '''if [ "$spec" = hosts ]; then
  mkdir -p "$PG/local" 2>/dev/null
  if [ ! -f "$base" ] && [ -f "$PG/hosts.local" ]; then
    cp -p "$PG/hosts.local" "$base" 2>/dev/null || { echo '{"ok":0,"err":"cannot migrate local hosts"}'; exit 0; }
  fi
  if [ ! -f "$base" ]; then : > "$base" 2>/dev/null || { echo '{"ok":0,"err":"cannot create local hosts"}'; exit 0; }; chmod 600 "$base" 2>/dev/null; fi
fi

'''
    if source.count(host_init_end) != 1:
        print("unexpected fileedit hosts initialization block", file=sys.stderr)
        return 1
    source = source.replace(host_init_end, host_init_end + LOCK_BLOCK + "\n", 1)
    anchor = '\ncase "$op" in\n  stat)'
    if source.count(anchor) != 1:
        print("unexpected fileedit command dispatch", file=sys.stderr)
        return 1
    source = source.replace(anchor, "\n" + CALL_BLOCK + 'case "$op" in\n  stat)', 1)
    target.write_text(source, encoding="utf-8")
    print("Installed serialized, stale-owner-aware editor write transactions.")
    return 0
if __name__ == "__main__":
    raise SystemExit(main())
