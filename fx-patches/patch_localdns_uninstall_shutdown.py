#!/usr/bin/env python3
"""Harden uninstall fallback when the local DNS watchdog helper is missing."""
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
                _mitm_warn "local DNS watchdog PID $_wd_pid did not exit; preserving $PG and refusing to race firewall cleanup"
              fi
              ;;
            *) PG_KEEP_DATA=1; _mitm_warn "local DNS watchdog PID $_wd_pid changed identity during shutdown; preserving $PG and refusing to race firewall cleanup" ;;
          esac
        fi
        ;;
      *) PG_KEEP_DATA=1; _mitm_warn "local DNS watchdog PID record exists but process identity cannot be confirmed; preserving $PG for safe retry" ;;
    esac
    ;;
  esac
fi
'''
if source.count(old) == 0:
    if new in source:
        print("Local DNS watchdog uninstall fallback already hardened.")
        raise SystemExit(0)
    raise SystemExit("local DNS watchdog fallback anchor changed; refusing unsafe patch")
if source.count(old) != 1:
    raise SystemExit("local DNS watchdog fallback is ambiguous")
source = source.replace(old, new, 1)
# If the watchdog cannot be positively stopped, do not proceed to firewall teardown:
# its recovery loop may still re-install FX-owned redirect rules.
source = source.replace(
    'PG_KEEP_DATA=1\\n    _mitm_warn "could not confirm stopping local DNS watchdog before firewall cleanup; preserving $PG and continuing best-effort cleanup"',
    'PG_KEEP_DATA=1\\n    PG_DNS_WATCHDOG_STOP_FAILED=1\\n    _mitm_warn "could not confirm stopping local DNS watchdog; aborting uninstall before firewall cleanup and preserving $PG"'
)
for phrase in (
    'local DNS watchdog PID $_wd_pid did not exit; preserving $PG and refusing to race firewall cleanup',
    'local DNS watchdog PID $_wd_pid changed identity during shutdown; preserving $PG and refusing to race firewall cleanup',
    'local DNS watchdog PID record exists but process identity cannot be confirmed; preserving $PG for safe retry',
):
    old_warning = '_mitm_warn "' + phrase + '"'
    new_warning = 'PG_DNS_WATCHDOG_STOP_FAILED=1; ' + old_warning
    source = source.replace('PG_KEEP_DATA=1; ' + old_warning, 'PG_KEEP_DATA=1; ' + new_warning)
gate = 'fi\\n\\n# ============================================================\\n# A1. 防火墙链'
if source.count(gate) != 1:
    raise SystemExit("uninstall DNS-stop gate anchor changed; refusing to continue")
source = source.replace(gate, 'fi\\n\\nif [ "\\${PG_DNS_WATCHDOG_STOP_FAILED:-0}" = 1 ]; then\\n  exit 1\\nfi\\n\\n# ============================================================\\n# A1. 防火墙链', 1)
uninstall.write_text(source, encoding="utf-8")
print("Hardened missing-helper DNS watchdog shutdown and cleanup gating.")uninstall.write_text(source, encoding="utf-8")
print("Hardened missing-helper DNS watchdog shutdown and cleanup gating.")uninstall.write_text(source, encoding="utf-8")
print("Hardened missing-helper DNS watchdog shutdown and cleanup gating.")uninstall.write_text(source, encoding="utf-8")
print("Hardened missing-helper DNS watchdog shutdown and cleanup gating.")
