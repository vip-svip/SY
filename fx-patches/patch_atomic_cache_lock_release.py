#!/usr/bin/env python3
"""Atomically release the per-URL Hosts and subscription cache locks."""
from pathlib import Path
import re
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
repo_root = Path(__file__).resolve().parents[1]
apply_file = module / "scripts/apply.sh"
subfetch_file = module / "scripts/subfetch.sh"
host_test = module / "scripts/tests/v1.0.0-hosts-cache-concurrency-regression.sh"
sub_test = module / "scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
root_proxy = module / "scripts/yulong-root-proxy.sh"
root_proxy_test = module / "scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh"
subfetch_stale_owner_test = module / "scripts/tests/v1.0.0-subfetch-stale-lock-ownership-regression.sh"
subfetch_stale_reclaim_test = module / "scripts/tests/v1.0.0-subfetch-stale-lock-reclaim-regression.sh"

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

def replace_shell_function(path: Path, function_name: str, replacement: str, label: str) -> None:
    source = path.read_text(encoding="utf-8")
    # Release archives have small formatting variants. Replace only the named
    # top-level POSIX function, bounded by its unindented closing brace.
    pattern = re.compile(r"(?ms)^" + re.escape(function_name) + r"\(\) \{\n.*?^\}")
    matches = list(pattern.finditer(source))
    if not matches:
        if 'mv "$LOCK" "$_release"' in source and '_lock_held=1' in source:
            return
        raise SystemExit(f"{path}: {label}: function boundary missing")
    if len(matches) != 1:
        raise SystemExit(f"{path}: {label}: expected one function, found {len(matches)}")
    updated = pattern.sub(lambda _: replacement, source, count=1)
    match = pattern.search(updated)
    if match is None:
        raise SystemExit(f"{path}: {label}: replacement function disappeared")
    function_body = match.group(0)
    if 'rm -f "$LOCK/pid"' in function_body or 'rmdir "$LOCK"' in function_body:
        raise SystemExit(f"{path}: {label}: legacy PID-first lock release remains")
    path.write_text(updated, encoding="utf-8")



# The release ZIP predates the repository-owned Root Proxy lock regression.
# Restore that canonical test into the staged module before validating inputs.
root_proxy_test_source = repo_root / "fx-module/scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh"
if not root_proxy_test_source.is_file() or root_proxy_test_source.stat().st_size < 3000:
    raise SystemExit("repository Root Proxy lock regression source is missing or incomplete")
root_proxy_test.parent.mkdir(parents=True, exist_ok=True)
if root_proxy_test_source.resolve() != root_proxy_test.resolve():
    shutil.copy2(root_proxy_test_source, root_proxy_test)

for required in (apply_file, subfetch_file, host_test, sub_test, root_proxy, root_proxy_test, subfetch_stale_owner_test, subfetch_stale_reclaim_test):
    if not required.is_file():
        raise SystemExit(f"restored FX cache-lock input missing: {required}")

# Release artifacts carry two stale-lock tests whose temp-directory suffixes
# differ between published versions. Normalize only the escaped TMPDIR prefix;
# keep each release's original unique suffix and accept already-correct copies.
_stale_tmp_old_prefix = 'mktemp -d "' + chr(92) + chr(36) + '{TMPDIR:-/tmp}/'
_stale_tmp_new_prefix = 'mktemp -d "' + chr(36) + '{TMPDIR:-/tmp}/'
for _stale_test in (subfetch_stale_owner_test, subfetch_stale_reclaim_test):
    _stale_text = _stale_test.read_text(encoding="utf-8")
    if _stale_tmp_old_prefix in _stale_text:
        _stale_text = _stale_text.replace(_stale_tmp_old_prefix, _stale_tmp_new_prefix)
        _stale_test.write_text(_stale_text, encoding="utf-8")
    _stale_text = _stale_test.read_text(encoding="utf-8")
    if _stale_tmp_old_prefix in _stale_text or _stale_tmp_new_prefix not in _stale_text:
        raise SystemExit(f"{_stale_test}: TMPDIR mktemp template is not safely expanded")

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
apply_source = apply_file.read_text(encoding="utf-8")
hosts_file_lock_v3 = "FX_HOSTS_FILE_LOCK_V3" in apply_source
if hosts_file_lock_v3:
    # The staged Release may already contain the repository-owned V3 atomic
    # regular-file lock. Validate its safety contract instead of demanding
    # obsolete directory/PID lock anchors.
    required_hosts_v3 = (
        'mv "$_hf_lock" "$_hf_release"',
        '_hf_read_lock_owner "$_hf_lock"',
        '_hf_read_lock_owner "$_hf_release"',
        '_hf_remove_lock_path "$_hf_release"',
        '( umask 077; set -C; printf ',
        '[ ! -L "$_hf_lock" ] && [ ! -e "$_hf_lock" ]',
    )
    missing_hosts_v3 = [token for token in required_hosts_v3 if token not in apply_source]
    if missing_hosts_v3:
        raise SystemExit(
            f"{apply_file}: V3 Hosts lock is incomplete: " + ", ".join(missing_hosts_v3)
        )
    if 'rm -f "$_hf_lock/pid"' in apply_source or 'rmdir "$_hf_lock"' in apply_source:
        raise SystemExit(f"{apply_file}: V3 Hosts lock retains legacy PID-first cleanup")
else:
    if old_hf_unlock in apply_source:
        replace_once(apply_file, old_hf_unlock, new_hf_unlock, "Hosts lock must release by atomic rename")
    elif (
        '_hf_release="$_hf_lock.release.' in apply_source
        and 'mv "$_hf_lock" "$_hf_release"' in apply_source
        and '_hf_release_owner=$(cat "$_hf_release/pid" 2>/dev/null || :)' in apply_source
        and 'rm -f "$_hf_lock/pid"' not in apply_source
        and 'rmdir "$_hf_lock"' not in apply_source
    ):
        print("Hosts cache lock already uses owner-checked atomic directory release.")
    else:
        raise SystemExit(f"{apply_file}: Hosts lock must release by atomic rename")

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
subfetch_source = subfetch_file.read_text(encoding="utf-8")
if "FX_SUBFETCH_FILE_LOCK_V2" in subfetch_source:
    # The canonical V2 implementation already creates a private regular-file
    # lock and releases it by owner-checked atomic rename. Preserve it rather
    # than trying to rewrite obsolete directory/PID lock anchors.
    required_v2 = (
        'mv "$LOCK" "$_sl_release"',
        '_sl_read_lock_owner "$LOCK"',
        '_sl_read_lock_owner "$_sl_stale"',
        '_sl_read_lock_owner "$_sl_release"',
        'if [ "$_sl_moved_owner" = "$_sl_owner" ]',
        'if [ "$_sl_release_owner" = "$$" ]',
    )
    missing_v2 = [token for token in required_v2 if token not in subfetch_source]
    if missing_v2:
        raise SystemExit(
            f"{subfetch_file}: V2 subscription lock is incomplete: " + ", ".join(missing_v2)
        )
    if 'rm -f "$LOCK/pid"' in subfetch_source or 'rmdir "$LOCK"' in subfetch_source:
        raise SystemExit(f"{subfetch_file}: V2 subscription lock retains legacy PID cleanup")
else:
    replace_once(subfetch_file, old_sub_unlock, new_sub_unlock, "subscription lock must release by atomic rename")


# The workflow stages the canonical Root Proxy before this shared lock patch.
# Do not rewrite it here: doing so would downgrade its private file lock back to
# the older directory/PID lock. Validate the staged source instead.
root_proxy_text = root_proxy.read_text(encoding="utf-8")
root_lock_pattern = re.compile(r"(?ms)^with_lock\(\) \{\n.*?^\}")
root_lock_matches = list(root_lock_pattern.finditer(root_proxy_text))
if len(root_lock_matches) != 1:
    raise SystemExit(f"{root_proxy}: expected one top-level with_lock function, found {len(root_lock_matches)}")
root_lock_body = root_lock_matches[0].group(0)
if "( umask 077; set -C; printf " not in root_lock_body or ' > "$LOCK" )' not in root_lock_body:
    raise SystemExit(f"{root_proxy}: Root Proxy must use a private noclobber regular-file lock")
if 'mv "$LOCK" "$_release"' not in root_lock_body:
    raise SystemExit(f"{root_proxy}: Root Proxy lock release must use an atomic rename")
if 'rm -f "$LOCK/pid"' in root_lock_body or 'rmdir "$LOCK"' in root_lock_body:
    raise SystemExit(f"{root_proxy}: obsolete directory/PID lock cleanup remains")

if "FX_SUBFETCH_FILE_LOCK_V2" not in subfetch_source:
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
if "FX_SUBFETCH_CONCURRENCY_CANONICAL_V1" in sub_test.read_text(encoding="utf-8"):
    # The repository-owned deterministic fixture already captures worker exit
    # codes and logs both workers. Validate that contract instead of trying to
    # rewrite old Release-specific anchors into a newer canonical test.
    canonical_source = sub_test.read_text(encoding="utf-8")
    canonical_required = (
        "release-curl",
        '_starts_before_release=$(grep -c',
        'if [ "$_starts_before_release" -ne 1 ]; then',
        'wait "$p1"; rc1=$?',
        'wait "$p2"; rc2=$?',
        'if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then',
        "worker 1 stdout/stderr:",
        "worker 2 stdout/stderr:",
        '[ "$count" = 2 ]',
        "actual_size",
        "meta_size",
        "actual_lines",
        "meta_lines",
        '[ ! -e "$T/state/subs/.lock.$key" ]',
    )
    missing = [token for token in canonical_required if token not in canonical_source]
    if missing:
        raise SystemExit(
            f"{sub_test}: canonical subscription concurrency fixture is incomplete: "
            + ", ".join(missing)
        )
    print("Canonical subscription concurrency fixture already gates transfers and reports both worker failures.")
else:
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
    

old_root_proxy_engine_stub = """for script in adguardhome.sh unbound.sh; do
  cat > "$MOD/scripts/$script" <<'SH'
#!/system/bin/sh
exit 0
SH
  chmod 0755 "$MOD/scripts/$script"
done"""
new_root_proxy_engine_stub = """for script in adguardhome.sh unbound.sh; do
  cat > "$MOD/scripts/$script" <<'SH'
#!/system/bin/sh
case "$1" in
  stop)
    if ! (umask 077; set -C; printf 'locked\\n' > "$TMP/engine.lock") 2>/dev/null; then
      printf 'overlap\\n' >> "$TMP/engine-overlap"
    fi
    /bin/sleep 0.04
    rm -f "$TMP/engine.lock"
    ;;
esac
exit 0
SH
  chmod 0755 "$MOD/scripts/$script"
done"""
root_proxy_test_source_text = root_proxy_test.read_text(encoding="utf-8")
if old_root_proxy_engine_stub in root_proxy_test_source_text:
    replace_once(
        root_proxy_test,
        old_root_proxy_engine_stub,
        new_root_proxy_engine_stub,
        "Root Proxy engine stub holds lock during stop",
    )
elif not ("engine-actions" in root_proxy_test_source_text and "engine-overlap" in root_proxy_test_source_text):
    raise SystemExit(f"{root_proxy_test}: unsupported Root Proxy engine stub fixture")

old_root_proxy_sleep_stub = """cat > "$BIN/sleep" <<'SH'
#!/system/bin/sh
exit 0
SH
"""
new_root_proxy_sleep_stub = """cat > "$BIN/sleep" <<'SH'
#!/bin/sh
case "$1" in
  1) /bin/sleep 0.01 ;;
  *) /bin/sleep "$@" ;;
esac
SH
"""
if 'export MP="$MOD" PG="$PG" PATH="$BIN:$PATH"' not in root_proxy_test_source_text:
    raise SystemExit(f"{root_proxy_test}: test environment export is missing")
if 'TMP="$TMP"' not in root_proxy_test_source_text:
    replace_once(
        root_proxy_test,
        'export MP="$MOD" PG="$PG" PATH="$BIN:$PATH"' + chr(10),
        'export MP="$MOD" PG="$PG" PATH="$BIN:$PATH" TMP="$TMP"' + chr(10),
        "Root Proxy test exports private temp path",
    )

if old_root_proxy_sleep_stub in root_proxy_test_source_text:
    replace_once(
        root_proxy_test,
        old_root_proxy_sleep_stub,
        new_root_proxy_sleep_stub,
        "Root Proxy waiter sleep must be bounded but observable",
    )
elif 'sleep 0.01' not in root_proxy_test_source_text:
    raise SystemExit(f"{root_proxy_test}: unsupported Root Proxy sleep stub")

root_proxy_test_done_marker = 'echo "PASS: Yulong Root Proxy lock recovers dead owners, preserves live owners and cleans up only after exit"\n'
root_proxy_test_done = '''grep -Fq '( umask 077; set -C; printf ' "$SOURCE" || {
  echo "FAIL: Root Proxy lock does not use private noclobber file creation" >&2; exit 1;
}
grep -Fq '_read_lock_owner() {' "$SOURCE" || {
  echo "FAIL: Root Proxy owner validation is missing" >&2; exit 1;
}
grep -Fq 'mv "$LOCK" "$_release"' "$SOURCE" || {
  echo "FAIL: Root Proxy release does not atomically rename the lock file" >&2; exit 1;
}
if grep -Fq 'while ! mkdir "$LOCK"' "$SOURCE" || grep -Fq 'rm -f "$LOCK/pid"' "$SOURCE" || grep -Fq 'rmdir "$LOCK"' "$SOURCE"; then
  echo "FAIL: legacy PID-directory Root Proxy lock remains" >&2; exit 1;
fi
printf '2147483647\\n' > "$LOCK"
sh "$SOURCE" stop >/dev/null
[ ! -e "$LOCK" ] || { echo "FAIL: stale regular Root Proxy file lock was not recovered" >&2; exit 1; }
printf '%s\\n' "$$" > "$LOCK"
set +e
sh "$SOURCE" stop >/dev/null 2>&1
file_rc=$?
set -e
[ "$file_rc" -eq 10 ] || { echo "FAIL: live regular Root Proxy file lock did not return busy (rc=$file_rc)" >&2; exit 1; }
[ "$(cat "$LOCK")" = "$$" ] || { echo "FAIL: live regular Root Proxy file lock owner changed" >&2; exit 1; }
rm -f "$LOCK"
sh "$SOURCE" stop > "$TMP/concurrent-a.log" 2>&1 & p1=$!
/bin/sleep 0.005
sh "$SOURCE" stop > "$TMP/concurrent-b.log" 2>&1 & p2=$!
wait "$p1" || { rc=$?; cat "$TMP/concurrent-a.log" "$TMP/concurrent-b.log" >&2; exit "$rc"; }
wait "$p2" || { rc=$?; cat "$TMP/concurrent-a.log" "$TMP/concurrent-b.log" >&2; exit "$rc"; }
[ ! -s "$TMP/engine-overlap" ] || {
  echo "FAIL: concurrent Root Proxy engine cleanup overlapped" >&2
  cat "$TMP/engine-overlap" >&2
  exit 1
}
[ ! -e "$LOCK" ] || { echo "FAIL: concurrent Root Proxy stops leaked lock file" >&2; exit 1; }
echo "PASS: Root Proxy atomic file lock, stale/live owners, legacy directory migration and concurrent serialization"
'''
root_proxy_test_text = root_proxy_test.read_text(encoding="utf-8")
if root_proxy_test_done_marker in root_proxy_test_text:
    replace_once(
        root_proxy_test,
        root_proxy_test_done_marker,
        root_proxy_test_done,
        "Root Proxy lock regression with concurrent stop",
    )
elif (
    'grep -Fq \'( umask 077; set -C; printf \' "$SOURCE"' in root_proxy_test_text
    and 'grep -Fq \'mv "$LOCK" "$_release"\' "$SOURCE"' in root_proxy_test_text
    and '[ ! -s "$TMP/engine-overlap" ]' in root_proxy_test_text
    and 'PASS: Root Proxy atomic file lock, stale/live owners, legacy directory migration and concurrent serialization' in root_proxy_test_text
) or (
    'PASS: Root Proxy atomic file lock, legacy migration, concurrent serialization and independent local-DNS engine ownership' in root_proxy_test_text
    and 'grep -Fq \'mv "$LOCK" "$_release"\' "$SOURCE"' in root_proxy_test_text
    and '[ ! -s "$TMP/engine-overlap" ]' in root_proxy_test_text
    and 'dns_engine_adguardhome=1' in root_proxy_test_text
    and 'trap cleanup_lock EXIT' in root_proxy_test_text
):
    # Newer Release archives already contain the full lock/concurrent-stop
    # regression with a different success marker. Preserve that stronger
    # fixture instead of failing on an obsolete exact-text anchor.
    pass
else:
    raise SystemExit(
        f"{root_proxy_test}: unsupported Root Proxy lock regression fixture; "
        "expected a known legacy marker or the complete current lock/concurrency checks"
    )

# Normalize a malformed PID fixture in older restored Release archives.
# Compose the two dollar signs separately so the shell PID remains literal in
# this Python source and is not confused with the tool/template interpolation.
root_proxy_test_text = root_proxy_test.read_text(encoding="utf-8")
root_proxy_test_text = root_proxy_test_text.replace(
    "printf '%s\\n' \"$\" > \"$LOCK\"",
    "printf '%s\\n' \"$" + "$" + "\" > \"$LOCK\"",
)
root_proxy_test_text = root_proxy_test_text.replace(
    '[ "$(cat "$LOCK")" = "$" ]',
    '[ "$(cat "$LOCK")" = "$' + '$' + '" ]',
)
broken_pid_line = "printf '%s\\n' \"$\" > \"$LOCK\""
broken_pid_check = '[ "$(cat "$LOCK")" = "$" ]'
if broken_pid_line in root_proxy_test_text or broken_pid_check in root_proxy_test_text:
    raise SystemExit(f"{root_proxy_test}: live lock fixture still uses an empty PID")
root_proxy_test.write_text(root_proxy_test_text, encoding="utf-8")

for path in (apply_file, subfetch_file, host_test, sub_test, root_proxy, root_proxy_test):
    path.chmod(0o755)
print("PASS: Hosts/subscription cache locks and Root Proxy atomic file-lock validation")
