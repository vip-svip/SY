#!/usr/bin/env python3
"""Atomically release the per-URL Hosts and subscription cache locks."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
apply_file = module / "scripts/apply.sh"
subfetch_file = module / "scripts/subfetch.sh"
host_test = module / "scripts/tests/v1.0.0-hosts-cache-concurrency-regression.sh"
sub_test = module / "scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"

def replace_once(path: Path, old: str, new: str, label: str) -> None:
    source = path.read_text(encoding="utf-8")
    if new in source:
        return
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{path}: {label}: expected one original anchor, found {count}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")

for required in (apply_file, subfetch_file, host_test, sub_test):
    if not required.is_file():
        raise SystemExit(f"restored FX cache-lock input missing: {required}")

# A waiter can race the old owner's rm-pid/rmdir-lock sequence. In that window
# cat lock/pid fails and set -e terminates the waiting worker.
old_hf_unlock = '''  _hf_unlock() {
    [ "$_hf_lock_held" = 1 ] || return 0
    _hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null)
    if [ "$_hf_owner" = "$$" ]; then rm -f "$_hf_lock/pid" 2>/dev/null; rmdir "$_hf_lock" 2>/dev/null || :; fi
    _hf_lock_held=0
  }'''
new_hf_unlock = '''  _hf_unlock() {
    [ "$_hf_lock_held" = 1 ] || return 0
    _hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null || :)
    if [ "$_hf_owner" = "$$" ]; then
      # Rename the complete owner directory away atomically. Do not expose an
      # empty lock/pid window to waiters running with errexit enabled.
      _hf_release="$_hf_lock.release.$$"
      _hf_release_try=0
      while [ -e "$_hf_release" ] && [ "$_hf_release_try" -lt 10 ]; do
        _hf_release_try=$((_hf_release_try+1))
        _hf_release="$_hf_lock.release.$$.$_hf_release_try"
      done
      if [ ! -e "$_hf_release" ] && mv "$_hf_lock" "$_hf_release" 2>/dev/null; then
        _hf_release_owner=$(cat "$_hf_release/pid" 2>/dev/null || :)
        if [ "$_hf_release_owner" = "$$" ]; then rm -rf "$_hf_release" 2>/dev/null || :; fi
      fi
    fi
    _hf_lock_held=0
    return 0
  }'''
replace_once(apply_file, old_hf_unlock, new_hf_unlock, "Hosts lock must release by atomic rename")

replace_once(
    apply_file,
    '_hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null)\n',
    '_hf_owner=$(cat "$_hf_lock/pid" 2>/dev/null || :)\n',
    "Hosts lock owner read must tolerate atomic release",
)
replace_once(
    apply_file,
    '_hf_owner2=$(cat "$_hf_lock/pid" 2>/dev/null)\n',
    '_hf_owner2=$(cat "$_hf_lock/pid" 2>/dev/null || :)\n',
    "Hosts stale-owner recheck must tolerate concurrent release",
)
old_sub_unlock = '''subfetch_unlock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  _sl_owner=$(cat "$LOCK/pid" 2>/dev/null)
  if [ "$_sl_owner" = "$$" ]; then rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null || :; fi
  LOCK_HELD=0
}'''
new_sub_unlock = '''subfetch_unlock() {
  [ "$LOCK_HELD" = 1 ] || return 0
  _sl_owner=$(cat "$LOCK/pid" 2>/dev/null || :)
  if [ "$_sl_owner" = "$$" ]; then
    # Waiters see either a live pid-bearing lock directory or no canonical lock.
    _sl_release="$LOCK.release.$$"
    _sl_release_try=0
    while [ -e "$_sl_release" ] && [ "$_sl_release_try" -lt 10 ]; do
      _sl_release_try=$((_sl_release_try+1))
      _sl_release="$LOCK.release.$$.$_sl_release_try"
    done
    if [ ! -e "$_sl_release" ] && mv "$LOCK" "$_sl_release" 2>/dev/null; then
      _sl_release_owner=$(cat "$_sl_release/pid" 2>/dev/null || :)
      if [ "$_sl_release_owner" = "$$" ]; then rm -rf "$_sl_release" 2>/dev/null || :; fi
    fi
  fi
  LOCK_HELD=0
  return 0
}'''
replace_once(subfetch_file, old_sub_unlock, new_sub_unlock, "subscription lock must release by atomic rename")

replace_once(
    subfetch_file,
    '_sl_owner=$(cat "$LOCK/pid" 2>/dev/null)\n',
    '_sl_owner=$(cat "$LOCK/pid" 2>/dev/null || :)\n',
    "subscription lock owner read must tolerate atomic release",
)
replace_once(
    subfetch_file,
    '_sl_again=$(cat "$LOCK/pid" 2>/dev/null)\n',
    '_sl_again=$(cat "$LOCK/pid" 2>/dev/null || :)\n',
    "subscription stale-owner recheck must tolerate concurrent release",
)
replace_once(
    subfetch_file,
    '_sl_moved_owner=$(cat "$_sl_stale/pid" 2>/dev/null)\n',
    '_sl_moved_owner=$(cat "$_sl_stale/pid" 2>/dev/null || :)\n',
    "subscription quarantined-owner read must tolerate concurrent release",
)
# Keep the CI failure actionable: an errexit-triggered worker must identify which
# concurrent request exited, rather than leaving only an empty test log.
replace_once(
    host_test,
    'wait "$p1"\nwait "$p2"\n',
    '''wait "$p1" || { rc=$?; echo "FAIL: Hosts cache worker A exited with $rc" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; echo "FAIL: Hosts cache worker B exited with $rc" >&2; exit "$rc"; }
''',
    "Hosts concurrency test must explain worker failure",
)
replace_once(
    host_test,
    '[ -s "$T/out.a" ] && [ -s "$T/out.b" ]\n',
    '[ -s "$T/out.a" ] && [ -s "$T/out.b" ] || { echo "FAIL: one or both Hosts workers did not produce output" >&2; exit 1; }\n',
    "Hosts concurrency test must explain missing output",
)
replace_once(
    sub_test,
    'wait "$p1"\nwait "$p2"\n',
    '''wait "$p1" || { rc=$?; echo "FAIL: subscription cache worker A exited with $rc" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; echo "FAIL: subscription cache worker B exited with $rc" >&2; exit "$rc"; }
''',
    "subscription concurrency test must explain worker failure",
)
for path in (apply_file, subfetch_file, host_test, sub_test):
    path.chmod(0o755)
print("PASS: Hosts and subscription cache locks use atomic owner-directory release")
