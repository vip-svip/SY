#!/usr/bin/env python3
"""Harden local DNS watchdog shutdown during FX uninstall."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
uninstall = root / "uninstall.sh"
if not uninstall.is_file():
    raise SystemExit("FX uninstall.sh is missing")
source = uninstall.read_text(encoding="utf-8")

old = '''elif [ -s "$PG/localdns-watchdog.pid" ]; then
  _wd_pid=$(cat "$PG/localdns-watchdog.pid" 2>/dev/null)
  case "$_wd_pid" in ''|*[!0-9]*|0|1) ;; *)
    if [ -r "/proc/$_wd_pid/cmdline" ]; then
      _wd_cmd=$(tr '\\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
      case "$_wd_cmd" in *"$MODDIR/scripts/localdns-watchdog.sh"*) kill -TERM "$_wd_pid" 2>/dev/null || : ;; esac
    fi ;;
  esac
fi
'''
new = '''elif [ -s "$PG/localdns-watchdog.pid" ]; then
  _wd_pid=$(cat "$PG/localdns-watchdog.pid" 2>/dev/null)
  case "$_wd_pid" in ''|*[!0-9]*|0|1) ;; *)
    if [ -L "$PG/localdns-watchdog.pid" ]; then
      PG_KEEP_DATA=1
      _mitm_warn "local DNS watchdog PID record is a symlink; aborting uninstall before firewall cleanup and preserving $PG"
      exit 1
    elif ! kill -0 "$_wd_pid" 2>/dev/null; then
      rm -f "$PG/localdns-watchdog.pid"
      _mitm_warn "cleared stale local DNS watchdog PID record for exited PID $_wd_pid"
    else
      _wd_cmd=''
      [ -r "/proc/$_wd_pid/cmdline" ] && _wd_cmd=$(tr '\\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
      case "$_wd_cmd" in
      *"$MODDIR/scripts/localdns-watchdog.sh"*)
        kill -TERM "$_wd_pid" 2>/dev/null || :
        _wd_wait=0
        while [ "$_wd_wait" -lt 10 ] && kill -0 "$_wd_pid" 2>/dev/null; do
          sleep 0.2
          _wd_wait=$((_wd_wait+1))
        done
        if kill -0 "$_wd_pid" 2>/dev/null; then
          _wd_cmd=''
          [ -r "/proc/$_wd_pid/cmdline" ] && _wd_cmd=$(tr '\\000' ' ' < "/proc/$_wd_pid/cmdline" 2>/dev/null)
          case "$_wd_cmd" in
            *"$MODDIR/scripts/localdns-watchdog.sh"*)
              kill -9 "$_wd_pid" 2>/dev/null || :
              _wd_wait=0
              while [ "$_wd_wait" -lt 10 ] && kill -0 "$_wd_pid" 2>/dev/null; do
                sleep 0.2
                _wd_wait=$((_wd_wait+1))
              done
              if kill -0 "$_wd_pid" 2>/dev/null; then
                PG_KEEP_DATA=1
                _mitm_warn "local DNS watchdog PID $_wd_pid did not exit; aborting uninstall before firewall cleanup and preserving $PG"
                exit 1
              fi
              ;;
            *) PG_KEEP_DATA=1; _mitm_warn "local DNS watchdog PID $_wd_pid changed identity during shutdown; aborting uninstall before firewall cleanup and preserving $PG"; exit 1 ;;
          esac
        fi
        ;;
      *) PG_KEEP_DATA=1; _mitm_warn "local DNS watchdog PID record exists but process identity cannot be confirmed; aborting uninstall before firewall cleanup and preserving $PG"; exit 1 ;;
      esac
    fi
    ;;
  esac
fi
'''
if source.count(old) == 0:
    if new in source or "FX_LOCALDNS_WATCHDOG_FAIL_CLOSED_BEGIN" in source:
        print("Local DNS watchdog uninstall fallback already hardened.")
    elif "localdns-watchdog.pid" not in source and "localdns-watchdog.sh" not in source:
        # Some published FX module revisions do not own this lifecycle.
        print("Published uninstall has no local-DNS watchdog hook; no fallback patch required.")
    else:
        # Older published ZIPs have a formatting variant of the PID fallback.
        # Rather than guessing which process their legacy block might signal,
        # insert a conservative guard before firewall teardown: a dead PID can
        # be discarded, but any live/ambiguous owner aborts uninstall and
        # preserves module state. This intentionally prefers a manual retry
        # over killing an unrelated process or tearing down active DNS rules.
        guard = '''# FX_LOCALDNS_WATCHDOG_FAIL_CLOSED_BEGIN
_PG_LOCALDNS=${PG:-${STATE_DIR:-/data/adb/privacyguard}}
_WD_FILE="$_PG_LOCALDNS/localdns-watchdog.pid"
if [ -L "$_WD_FILE" ]; then
  PG_KEEP_DATA=1
  _mitm_warn "local DNS watchdog PID record is a symlink; aborting uninstall before firewall cleanup and preserving $_PG_LOCALDNS"
  exit 1
elif [ -s "$_WD_FILE" ]; then
  _wd_pid=$(cat "$_WD_FILE" 2>/dev/null || :)
  case "$_wd_pid" in
    ''|*[!0-9]*|0|1)
      PG_KEEP_DATA=1
      _mitm_warn "local DNS watchdog PID record is invalid; aborting uninstall before firewall cleanup and preserving $_PG_LOCALDNS"
      exit 1
      ;;
    *)
      if kill -0 "$_wd_pid" 2>/dev/null; then
        PG_KEEP_DATA=1
        _mitm_warn "local DNS watchdog PID $_wd_pid is still live but this release has an unknown shutdown layout; aborting uninstall before firewall cleanup and preserving $_PG_LOCALDNS"
        exit 1
      fi
      rm -f "$_WD_FILE"
      _mitm_warn "cleared stale local DNS watchdog PID record for exited PID $_wd_pid"
      ;;
  esac
fi
# FX_LOCALDNS_WATCHDOG_FAIL_CLOSED_END
'''
        firewall_anchor = 'if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then'
        if firewall_anchor not in source:
            raise SystemExit("local DNS watchdog fallback anchor changed and no safe pre-firewall insertion point exists")
        source = source.replace(firewall_anchor, guard + "\\n" + firewall_anchor, 1)
else:
    if source.count(old) != 1:
        raise SystemExit("local DNS watchdog fallback is ambiguous")
    source = source.replace(old, new, 1)

# The normal helper path must also stop uninstall if it cannot confirm shutdown.
old_warning = 'could not confirm stopping local DNS watchdog before firewall cleanup; preserving $PG and continuing best-effort cleanup'
new_warning = 'could not confirm stopping local DNS watchdog; aborting uninstall before firewall cleanup and preserving $PG'
if old_warning in source:
    source = source.replace(old_warning, new_warning, 1)
    line = '_mitm_warn "' + new_warning + '"'
    if line in source:
        source = source.replace(line, line + '; exit 1', 1)
elif new_warning in source:
    # Idempotent when the helper failure path was already updated.
    line = '_mitm_warn "' + new_warning + '"'
    if line in source and line + '; exit 1' not in source:
        source = source.replace(line, line + '; exit 1', 1)

# Keep the uninstall regression aligned with the fail-closed contract.
regression = root / "scripts/tests/v1.0.0-uninstall-stops-localdns-watchdog-before-firewall-regression.sh"
if regression.is_file():
    test_source = regression.read_text(encoding="utf-8")
    test_source = test_source.replace(
        "could not confirm stopping local DNS watchdog before firewall cleanup",
        "could not confirm stopping local DNS watchdog; aborting uninstall before firewall cleanup"
    )
    regression.write_text(test_source, encoding="utf-8")

uninstall.write_text(source, encoding="utf-8")
print("Hardened local DNS watchdog shutdown; uninstall now fails closed before firewall teardown.")
