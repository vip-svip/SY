#!/usr/bin/env python3
"""Atomically release the per-URL Hosts and subscription cache locks."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
apply_file = module / "scripts/apply.sh"
subfetch_file = module / "scripts/subfetch.sh"
host_test = module / "scripts/tests/v1.0.0-hosts-cache-concurrency-regression.sh"
sub_test = module / "scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
root_proxy = module / "scripts/yulong-root-proxy.sh"
root_proxy_test = module / "scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh"

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

def replace_if_present(path: Path, old: str, new: str, label: str) -> bool:
    """Optional diagnostic instrumentation for known release fixture variants."""
    source = path.read_text(encoding="utf-8")
    if new in source:
        return True
    count = source.count(old)
    if count == 0:
        return False
    if count != 1:
        raise SystemExit(f"{path}: {label}: expected one optional anchor, found {count}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return True

for required in (apply_file, subfetch_file, host_test, sub_test, root_proxy, root_proxy_test):
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


pid_literal = "$" + "$"
old_root_proxy_lock = '''with_lock() {
  _tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    _owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
    case "$_owner" in
      ''|*[!0-9]*)
        # Allow the owner to publish a PID immediately after mkdir.
        if [ ! -e "$LOCK/pid" ] && [ "$_tries" -ge 3 ]; then
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
      *)
        if ! kill -0 "$_owner" 2>/dev/null; then
          rm -f "$LOCK/pid" 2>/dev/null || :
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
    esac
    _tries=$((_tries+1))
    [ "$_tries" -lt 20 ] || { echo "root DNS proxy update is busy" >&2; return 10; }
    sleep 1
  done
  if ! printf '%s\\n' "__PID__" > "$LOCK/pid"; then
    rmdir "$LOCK" 2>/dev/null || :
    echo "cannot record root DNS proxy lock owner" >&2
    return 10
  fi
  cleanup_lock() {
    rm -f "$LOCK/pid" 2>/dev/null || :
    rmdir "$LOCK" 2>/dev/null || :
  }
  # Signal handlers exit first; EXIT performs the one authoritative cleanup.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}'''.replace("__PID__", pid_literal)

new_root_proxy_lock = '''with_lock() {
  _tries=0
  _lock_held=0
  while :; do
    if [ ! -L "$LOCK" ] && mkdir "$LOCK" 2>/dev/null; then
      _lock_held=1
      break
    fi
    [ ! -L "$LOCK" ] || { echo "unsafe root DNS proxy lock path" >&2; return 11; }
    [ ! -L "$LOCK/pid" ] || { echo "unsafe root DNS proxy lock owner record" >&2; return 11; }
    _owner=$(cat "$LOCK/pid" 2>/dev/null || :)
    case "$_owner" in
      ''|*[!0-9]*)
        # Give a newly-created owner a short PID publication window. If it
        # remains empty, atomically quarantine the complete directory.
        if [ ! -e "$LOCK/pid" ] && [ "$_tries" -ge 3 ]; then
          _stale="$LOCK.stale.__PID__.$_tries"
          if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] && mv "$LOCK" "$_stale" 2>/dev/null; then
            _moved_owner=$(cat "$_stale/pid" 2>/dev/null || :)
            if [ -z "$_moved_owner" ]; then
              rm -rf "$_stale" 2>/dev/null || :
            elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
              mv "$_stale" "$LOCK" 2>/dev/null || :
            fi
          fi
        fi
        ;;
      *)
        if ! kill -0 "$_owner" 2>/dev/null; then
          _owner_again=$(cat "$LOCK/pid" 2>/dev/null || :)
          if [ "$_owner_again" = "$_owner" ] && ! kill -0 "$_owner_again" 2>/dev/null; then
            _stale="$LOCK.stale.__PID__.$_tries"
            if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] && mv "$LOCK" "$_stale" 2>/dev/null; then
              _moved_owner=$(cat "$_stale/pid" 2>/dev/null || :)
              if [ "$_moved_owner" = "$_owner" ] && ! kill -0 "$_moved_owner" 2>/dev/null; then
                rm -rf "$_stale" 2>/dev/null || :
              elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
                mv "$_stale" "$LOCK" 2>/dev/null || :
              fi
            fi
          fi
        fi
        ;;
    esac
    _tries=$((_tries+1))
    [ "$_tries" -lt 20 ] || { echo "root DNS proxy update is busy" >&2; return 10; }
    sleep 1
  done
  if ! (umask 077; set -C; printf '%s\\n' "__PID__" > "$LOCK/pid") 2>/dev/null; then
    _release="$LOCK.failed.__PID__"
    if [ ! -e "$_release" ] && [ ! -L "$_release" ] && mv "$LOCK" "$_release" 2>/dev/null; then
      rm -rf "$_release" 2>/dev/null || :
    fi
    _lock_held=0
    echo "cannot record root DNS proxy lock owner" >&2
    return 10
  fi
  cleanup_lock() {
    [ "$_lock_held" = 1 ] || return 0
    _owner=$(cat "$LOCK/pid" 2>/dev/null || :)
    if [ "$_owner" = "__PID__" ]; then
      _release="$LOCK.release.__PID__"
      _release_try=0
      while { [ -e "$_release" ] || [ -L "$_release" ]; } && [ "$_release_try" -lt 20 ]; do
        _release_try=$((_release_try+1))
        _release="$LOCK.release.__PID__.$_release_try"
      done
      if [ ! -e "$_release" ] && [ ! -L "$_release" ] && mv "$LOCK" "$_release" 2>/dev/null; then
        _release_owner=$(cat "$_release/pid" 2>/dev/null || :)
        if [ "$_release_owner" = "__PID__" ]; then rm -rf "$_release" 2>/dev/null || :; fi
      fi
    fi
    _lock_held=0
    return 0
  }
  # Signal handlers exit first; EXIT performs the one authoritative cleanup.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}'''.replace("__PID__", pid_literal)
replace_once(root_proxy, old_root_proxy_lock, new_root_proxy_lock, "Root Proxy lock must use atomic directory rename")

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

replace_if_present(
    host_test,
    """pg_fetch_t() {
  sleep 0.3
  printf 'worker-%s.example\\nsecond-line.example\\n' "$" > "$2"
  return 0
}""",
    """pg_fetch_t() {
  printf 'START|%s\\n' "$" >> "$TEST_ROOT/fetch-events"
  _hf_gate_tries=0
  while [ ! -e "$TEST_ROOT/release-fetch" ]; do
    _hf_gate_tries=$((_hf_gate_tries+1))
    [ "$_hf_gate_tries" -lt 500 ] || { echo "mock Hosts fetch gate timed out" >&2; return 70; }
    sleep 0.01
  done
  printf 'worker-%s.example\\nsecond-line.example\\n' "$" > "$2"
  printf 'END|%s\\n' "$" >> "$TEST_ROOT/fetch-events"
  return 0
}""",
    "Hosts concurrency test must hold first fetch while second contends",
)
replace_if_present(
    host_test,
    """ "$T/worker.sh" a & p1=$!
"$T/worker.sh" b & p2=$!
wait "$p1" || { rc=$?; echo "FAIL: Hosts cache worker A exited with $rc" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; echo "FAIL: Hosts cache worker B exited with $rc" >&2; exit "$rc"; }""",
    """ "$T/worker.sh" a & p1=$!
"$T/worker.sh" b & p2=$!
_gate_tries=0
while [ ! -s "$T/fetch-events" ] && [ "$_gate_tries" -lt 200 ]; do
  _gate_tries=$((_gate_tries+1))
  sleep 0.01
done
sleep 0.25
_starts_before_release=$(grep -c '^START|' "$T/fetch-events" 2>/dev/null || echo 0)
touch "$T/release-fetch"
if [ "$_starts_before_release" -ne 1 ]; then
  echo "FAIL: second same-URL Hosts fetch entered while first response was blocked (START count=$_starts_before_release)" >&2
  cat "$T/fetch-events" >&2 || :
  wait "$p1" || :
  wait "$p2" || :
  exit 1
fi
wait "$p1" || { rc=$?; echo "FAIL: Hosts cache worker A exited with $rc" >&2; cat "$T/fetch-events" >&2 || :; exit "$rc"; }
wait "$p2" || { rc=$?; echo "FAIL: Hosts cache worker B exited with $rc" >&2; cat "$T/fetch-events" >&2 || :; exit "$rc"; }""",
    "Hosts concurrency test must deterministically gate two same-URL workers",
)
replace_if_present(
    host_test,
    """[ "$actual" = "$expected" ] || { echo 'FAIL: same-URL concurrent cache commit left a mismatched SHA-256 sidecar' >&2; exit 1; }""",
    """[ "$actual" = "$expected" ] || { echo "FAIL: same-URL cache SHA mismatch actual=$actual expected=$expected" >&2; echo "cache body:" >&2; cat "$cache" >&2 || :; echo "sidecar:" >&2; cat "$cache.sha256" >&2 || :; echo "fetch event timeline:" >&2; cat "$T/fetch-events" >&2 || :; find "$T/state/cache/rules" -maxdepth 1 -type f -print >&2; exit 1; }""",
    "Hosts cache hash mismatch must expose body, sidecar and fetch timeline",
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

# The restored release artifact already includes per-curl START/END markers.
# Its worker launch syntax differs from the repository fixture, so do not force
# a second, brittle rewrite of those commands; the count-failure assertion below
# prints the event log and both worker responses for diagnosis.
# Add shell xtrace to the two known restored-release worker forms. These are
# optional diagnostic upgrades because root and release fixture launch syntax
# have differed over time. The concurrency assertions stay unchanged.
replace_if_present(
    sub_test,
    """PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" 'https://example.invalid/rules' --force > "$T/out1" & p1=$!
""",
    """# FX_SUBFETCH_WORKER_TRACE_A_V1
PS4='FXSUB-A ' PG="$T/state" MODDIR="$T/module" sh -x "$T/module/scripts/subfetch.sh" 'https://example.invalid/rules' --force > "$T/out1" 2> "$T/trace1" & p1=$!
""",
    "subscription worker A shell trace",
)
replace_if_present(
    sub_test,
    """PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" 'https://example.invalid/rules' --force > "$T/out2" & p2=$!
""",
    """# FX_SUBFETCH_WORKER_TRACE_B_V1
PS4='FXSUB-B ' PG="$T/state" MODDIR="$T/module" sh -x "$T/module/scripts/subfetch.sh" 'https://example.invalid/rules' --force > "$T/out2" 2> "$T/trace2" & p2=$!
""",
    "subscription worker B shell trace",
)

# Instrument filesystem lock operations at the command boundary. Shell xtrace can
# show the same PID path in separate files but does not preserve cross-process
# ordering. These wrappers timestamp successful/failed mkdir, mv, rm and rmdir
# operations on the subscription lock pathname, so a stale reaper or unexpected
# cleanup is directly attributable to one process.
const_lock_ops_block = r"""
# FX_SUBFETCH_LOCK_EVENT_WRAPPERS_V1
cat > "$T/bin/mkdir" <<'FX_MKDIR'
#!/bin/sh
lock=''
for arg in "$@"; do case "$arg" in */subs/.lock.*) lock=$arg ;; esac; done
before=absent; owner=-
if [ -n "$lock" ] && [ -d "$lock" ]; then before=present; owner=$(cat "$lock/pid" 2>/dev/null || echo missing); fi
rc=0
/usr/bin/mkdir "$@" || rc=$?
if [ -n "$lock" ]; then
  after=absent; new_owner=-
  if [ -d "$lock" ]; then after=present; new_owner=$(cat "$lock/pid" 2>/dev/null || echo missing); fi
  inode_before=$(stat -c %i "$lock" 2>/dev/null || echo missing)
  printf 'MKDIR|pid=%s|ppid=%s|time=%s|rc=%s|args=%s|path=%s|before=%s:%s|after=%s:%s|inode=%s\n' "$" "$PPID" "$(date +%s.%N 2>/dev/null || date +%s)" "$rc" "$*" "$lock" "$before" "$owner" "$after" "$new_owner" "$inode_before" >> "$TEST_ROOT/lock-events"
fi
exit "$rc"
FX_MKDIR
cat > "$T/bin/mv" <<'FX_MV'
#!/bin/sh
set -- "$@"
src=''; dst=''
for arg in "$@"; do src=$dst; dst=$arg; done
case "$src $dst" in
  *"/subs/.lock."*)
    owner=$(cat "$src/pid" 2>/dev/null || echo missing)
    rc=0; /usr/bin/mv "$@" || rc=$?
    src_after=absent; dst_after=absent
    [ ! -e "$src" ] || src_after=present
    [ ! -e "$dst" ] || dst_after=present
    dst_owner=$(cat "$dst/pid" 2>/dev/null || echo missing)
    printf 'MV|pid=%s|ppid=%s|time=%s|rc=%s|src=%s|dst=%s|owner_before=%s|src_after=%s|dst_after=%s|dst_owner=%s\n' "$" "$PPID" "$(date +%s.%N 2>/dev/null || date +%s)" "$rc" "$src" "$dst" "$owner" "$src_after" "$dst_after" "$dst_owner" >> "$TEST_ROOT/lock-events"
    exit "$rc"
    ;;
esac
exec /usr/bin/mv "$@"
FX_MV
cat > "$T/bin/rm" <<'FX_RM'
#!/bin/sh
matched=0
for arg in "$@"; do case "$arg" in */subs/.lock.*) matched=1 ;; esac; done
if [ "$matched" = 1 ]; then
  printf 'RM_BEGIN|pid=%s|ppid=%s|time=%s|args=%s\n' "$" "$PPID" "$(date +%s.%N 2>/dev/null || date +%s)" "$*" >> "$TEST_ROOT/lock-events"
  rc=0; /usr/bin/rm "$@" || rc=$?
  printf 'RM_END|pid=%s|ppid=%s|time=%s|rc=%s|args=%s\n' "$" "$PPID" "$(date +%s.%N 2>/dev/null || date +%s)" "$rc" "$*" >> "$TEST_ROOT/lock-events"
  exit "$rc"
fi
exec /usr/bin/rm "$@"
FX_RM
cat > "$T/bin/rmdir" <<'FX_RMDIR'
#!/bin/sh
matched=0
for arg in "$@"; do case "$arg" in */subs/.lock.*) matched=1 ;; esac; done
if [ "$matched" = 1 ]; then
  printf 'RMDIR_BEGIN|pid=%s|ppid=%s|time=%s|args=%s\n' "$" "$PPID" "$(date +%s.%N 2>/dev/null || date +%s)" "$*" >> "$TEST_ROOT/lock-events"
  rc=0; /usr/bin/rmdir "$@" || rc=$?
  printf 'RMDIR_END|pid=%s|ppid=%s|time=%s|rc=%s|args=%s\n' "$" "$PPID" "$(date +%s.%N 2>/dev/null || date +%s)" "$rc" "$*" >> "$TEST_ROOT/lock-events"
  exit "$rc"
fi
exec /usr/bin/rmdir "$@"
FX_RMDIR
chmod 0755 "$T/bin/mkdir" "$T/bin/mv" "$T/bin/rm" "$T/bin/rmdir"
"""
if "FX_SUBFETCH_LOCK_EVENT_WRAPPERS_V1" not in sub_test.read_text(encoding="utf-8"):
    if not replace_if_present(
        sub_test,
        'export TEST_ROOT="$T/state"\nexport PATH="$T/bin:$PATH"\n',
        'export TEST_ROOT="$T/state"\nexport PATH="$T/bin:$PATH"\n' + const_lock_ops_block,
        "subscription lock operation event wrappers (split env)",
    ):
        replace_if_present(
            sub_test,
            'export TEST_ROOT="$T/state" PATH="$T/bin:$PATH"\n',
            'export TEST_ROOT="$T/state" PATH="$T/bin:$PATH"\n' + const_lock_ops_block,
            "subscription lock operation event wrappers (combined env)",
        )

# Do not require one particular restored-release worker launch spelling.
# Optional per-source-tree tracing above is sufficient when the anchor exists;
# failure diagnostics still print both worker outputs and the cache state.
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
    '[ "$(cat "$T/state/count")" -eq 2 ] || { echo "FAIL: expected exactly two serialized curl requests, got $(cat "$T/state/count" 2>/dev/null || echo missing)" >&2; echo "curl event log:" >&2; cat "$T/state/curl-events" >&2 || :; echo "lock operation log:" >&2; cat "$T/state/lock-events" >&2 || :; echo "worker A lock trace:" >&2; cat "$T/trace1" >&2 || :; echo "worker B lock trace:" >&2; cat "$T/trace2" >&2 || :; cat "$T/out1" "$T/out2" >&2; exit 1; }\n',
    "subscription concurrency test must explain lost or overlapping requests",
)
replace_once(
    sub_test,
    '[ ! -d "$T/state/subs/.lock.$key" ]\n',
    '[ ! -d "$T/state/subs/.lock.$key" ] || { echo "FAIL: subscription lock directory leaked after both workers exited" >&2; find "$T/state/subs/.lock.$key" -maxdepth 2 -print >&2; exit 1; }\n',
    "subscription concurrency test must explain lock directory leak",
)

replace_once(
    root_proxy_test,
    'for script in adguardhome.sh unbound.sh; do\n  cat > "$MOD/scripts/$script" <<\\'SH\\'\n#!/system/bin/sh\nexit 0\nSH\n  chmod 0755 "$MOD/scripts/$script"\ndone',
    'for script in adguardhome.sh unbound.sh; do\n  cat > "$MOD/scripts/$script" <<\\'SH\\'\n#!/system/bin/sh\n[ "$1" != stop ] || /bin/sleep 0.04\nexit 0\nSH\n  chmod 0755 "$MOD/scripts/$script"\ndone',
    "Root Proxy engine stub holds lock during stop",
)
replace_once(
    root_proxy_test,
    'cat > "$BIN/sleep" <<\\'SH\\'\n#!/system/bin/sh\nexit 0\nSH\n',
    'cat > "$BIN/sleep" <<\\'SH\\'\n#!/system/bin/sh\ncase "$1" in\n  1) /bin/sleep 0.01 ;;\n  *) /bin/sleep "$@" ;;\nesac\nSH\n',
    "Root Proxy waiter sleep must be bounded but observable",
)
replace_once(
    root_proxy_test,
    'echo "PASS: Yulong Root Proxy lock recovers dead owners, preserves live owners and cleans up only after exit"\\n',
    '''grep -Fq 'mv "$LOCK" "$_release"' "$SOURCE" || {
  echo "FAIL: Root Proxy unlock does not atomically rename its owner directory" >&2; exit 1;
}
if grep -Fq 'rm -f "$LOCK/pid" 2>/dev/null || :' "$SOURCE"; then
  echo "FAIL: Root Proxy unlock still removes PID before the lock directory" >&2; exit 1;
fi
if grep -Fq 'rmdir "$LOCK" 2>/dev/null || :' "$SOURCE"; then
  echo "FAIL: Root Proxy unlock still exposes a PID-less directory window" >&2; exit 1;
fi
# Two stop operations overlap while the mock engines keep the first owner
# inside the protected section. The waiter must acquire after atomic release.
sh "$SOURCE" stop > "$TMP/concurrent-a.log" 2>&1 & p1=$!
/bin/sleep 0.005
sh "$SOURCE" stop > "$TMP/concurrent-b.log" 2>&1 & p2=$!
wait "$p1" || { rc=$?; cat "$TMP/concurrent-a.log" "$TMP/concurrent-b.log" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; cat "$TMP/concurrent-a.log" "$TMP/concurrent-b.log" >&2; exit "$rc"; }
[ ! -e "$LOCK" ] || { echo "FAIL: concurrent Root Proxy stops leaked their lock" >&2; exit 1; }
[ -z "$(find "$PG" -maxdepth 1 -name 'yulong-root-proxy.lock.*' -print -quit)" ] || {
  echo "FAIL: Root Proxy stale/release directory leaked" >&2; exit 1;
}
echo "PASS: Yulong Root Proxy lock uses atomic owner-directory release, recovers stale owners, preserves live owners and serializes concurrent stops"
''',
    "Root Proxy lock regression with concurrent stop",
)

for path in (apply_file, subfetch_file, host_test, sub_test, root_proxy, root_proxy_test):
    path.chmod(0o755)
print("PASS: Hosts and subscription cache locks use atomic owner-directory release")
