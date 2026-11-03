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
    count = source.count(old)
    if count == 0:
        # The same expression may legitimately occur in both the unlock trap
        # and the waiter loop. A patched unlock must not make the waiter patch
        # silently skip its still-unpatched occurrence.
        if new in source:
            return
        raise SystemExit(f"{path}: {label}: original and patched anchors are both missing")
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

# Trace the actual mock curl heredoc using stable line anchors. START/END are
# patched independently so a partial fixture patch can recover on rerun.
if "FX_SUBFETCH_CURL_TRACE_V1" not in sub_test.read_text(encoding="utf-8"):
    replace_once(
        sub_test,
        'countfile="$TEST_ROOT/count"\n',
        'countfile="$TEST_ROOT/count"\n# FX_SUBFETCH_CURL_TRACE_V1\nprintf "START|%s\\n" "$$" >> "$TEST_ROOT/curl-events"\n',
        "subscription mock must record each curl start",
    )
if "FX_SUBFETCH_CURL_TRACE_END_V1" not in sub_test.read_text(encoding="utf-8"):
    replace_once(
        sub_test,
        'fi\nCURL\n',
        'fi\n# FX_SUBFETCH_CURL_TRACE_END_V1\nprintf "END|%s\\n" "$$" >> "$TEST_ROOT/curl-events"\nCURL\n',
        "subscription mock must record each curl completion",
    )

# Capture shell xtrace independently from each worker's JSON stdout.
replace_once(
    sub_test,
    'PG="$T/state" sh "$MODULE/scripts/subfetch.sh" "$URL" --force > "$T/out1" 2> "$T/err1" &\n',
    'PS4="FXSUB " PG="$T/state" sh -x "$MODULE/scripts/subfetch.sh" "$URL" --force > "$T/out1" 2> "$T/trace1" &\n',
    "subscription worker A must capture lock trace",
)
replace_once(
    sub_test,
    'PG="$T/state" sh "$MODULE/scripts/subfetch.sh" "$URL" --force > "$T/out2" 2> "$T/err2" &\n',
    'PS4="FXSUB " PG="$T/state" sh -x "$MODULE/scripts/subfetch.sh" "$URL" --force > "$T/out2" 2> "$T/trace2" &\n',
    "subscription worker B must capture lock trace",
)

# Capture the two shell lock paths on failure. This shows whether both workers
# acquire the per-URL mkdir lock or whether a waiter reclaims a live PID.
replace_once(
    sub_test,
    'PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" \'https://example.invalid/rules\' --force > "$T/out1" & p1=$!\n',
    'PS4=\'+[$$] \' PG="$T/state" MODDIR="$T/module" sh -x "$T/module/scripts/subfetch.sh" \'https://example.invalid/rules\' --force > "$T/out1" 2> "$T/trace1" & p1=$!\n',
    "subscription worker A must capture lock trace",
)
replace_once(
    sub_test,
    'PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" \'https://example.invalid/rules\' --force > "$T/out2" & p2=$!\n',
    'PS4=\'+[$$] \' PG="$T/state" MODDIR="$T/module" sh -x "$T/module/scripts/subfetch.sh" \'https://example.invalid/rules\' --force > "$T/out2" 2> "$T/trace2" & p2=$!\n',
    "subscription worker B must capture lock trace",
)
# The legacy test uses set -e with bare assertions. When one metadata/lock
# invariant fails it previously exited with an empty log, so add precise failure
# output while keeping the same assertions and exit behavior.
replace_once(
    sub_test,
    '[ -s "$body" ] && [ -s "$meta" ]\n',
    '[ -s "$body" ] && [ -s "$meta" ] || { echo "FAIL: subscription body or metadata sidecar missing" >&2; find "$T/state/subs" -maxdepth 2 -print >&2; exit 1; }\n',
    "subscription concurrency test must explain missing cache files",
)
replace_once(
    sub_test,
    '[ "$actual_size" = "$meta_size" ]\n',
    '[ "$actual_size" = "$meta_size" ] || { echo "FAIL: subscription metadata size mismatch body=$actual_size meta=$meta_size" >&2; cat "$meta" >&2; exit 1; }\n',
    "subscription concurrency test must explain size metadata mismatch",
)
replace_once(
    sub_test,
    '[ "$actual_lines" = "$meta_lines" ]\n',
    '[ "$actual_lines" = "$meta_lines" ] || { echo "FAIL: subscription metadata line mismatch body=$actual_lines meta=$meta_lines" >&2; cat "$meta" >&2; exit 1; }\n',
    "subscription concurrency test must explain line metadata mismatch",
)
replace_once(
    sub_test,
    '[ "$(cat "$T/state/count")" -eq 2 ]\n',
    '[ "$(cat "$T/state/count")" -eq 2 ] || { echo "FAIL: expected exactly two serialized curl requests, got $(cat "$T/state/count" 2>/dev/null || echo missing)" >&2; echo "curl event log:" >&2; cat "$T/state/curl-events" >&2 || :; echo "worker A lock trace:" >&2; cat "$T/trace1" >&2 || :; echo "worker B lock trace:" >&2; cat "$T/trace2" >&2 || :; cat "$T/out1" "$T/out2" >&2; exit 1; }\n',
    "subscription concurrency test must explain lost or overlapping requests",
)
replace_once(
    sub_test,
    '[ ! -d "$T/state/subs/.lock.$key" ]\n',
    '[ ! -d "$T/state/subs/.lock.$key" ] || { echo "FAIL: subscription lock directory leaked after both workers exited" >&2; find "$T/state/subs/.lock.$key" -maxdepth 2 -print >&2; exit 1; }\n',
    "subscription concurrency test must explain lock directory leak",
)
for path in (apply_file, subfetch_file, host_test, sub_test):
    path.chmod(0o755)
print("PASS: Hosts and subscription cache locks use atomic owner-directory release")
