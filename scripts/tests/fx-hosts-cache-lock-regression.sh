#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_hosts_file_lock.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "Hosts cache lock patcher missing"
python3 -m py_compile "$PATCHER" || fail "Hosts cache lock patcher Python syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-hosts-cache-lock.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"
mkdir -p "$MOD/scripts"
if [ -n "${1:-}" ]; then
  [ -s "$1/scripts/apply.sh" ] || fail "restored apply.sh missing"
  cp "$1/scripts/apply.sh" "$MOD/scripts/apply.sh"
else
  cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/system/bin/sh
apply_hosts_cache() {
  _hf_lock="$PG/cache/rules/.lock.$_hf_key"
  # Legacy lock body replaced by the patcher.
  # Keep a verified previous generation.
  return 0
}
APPLY
fi
chmod 0755 "$MOD/scripts/apply.sh"
python3 "$PATCHER" "$MOD" >/dev/null || fail "Hosts cache patcher rejected its apply.sh anchors"
python3 "$PATCHER" "$MOD" >/dev/null || fail "Hosts cache patcher is not idempotent"
sh -n "$MOD/scripts/apply.sh" || fail "patched apply.sh shell syntax invalid"
grep -Fq '# FX_HOSTS_FILE_LOCK_V3' "$MOD/scripts/apply.sh" || fail "V3 lock marker missing"
if grep -Fq 'rm -rf "$_hf_path"' "$MOD/scripts/apply.sh"; then
  fail "legacy lock cleanup still recursively removes unknown directory contents"
fi
HELPERS="$T/lock-helpers.sh"
sed -n '/^  _hf_read_lock_owner() {/,/^  }/p' "$MOD/scripts/apply.sh" > "$HELPERS"
sed -n '/^  _hf_remove_lock_path() {/,/^  }/p' "$MOD/scripts/apply.sh" >> "$HELPERS"
[ -s "$HELPERS" ] || fail "production lock helpers could not be extracted"
sh -n "$HELPERS" || fail "extracted lock helpers shell syntax invalid"
. "$HELPERS"

# Empty lock directory, PID-only legacy directory and canonical file lock are safe to retire.
mkdir "$T/empty-lock"
_hf_remove_lock_path "$T/empty-lock" || fail "empty legacy lock directory was not removed"
[ ! -e "$T/empty-lock" ] || fail "empty lock directory remains"
mkdir "$T/pid-lock"
printf '12345\n' > "$T/pid-lock/pid"
[ "$(_hf_read_lock_owner "$T/pid-lock")" = 12345 ] || fail "regular legacy PID owner was not read"
_hf_remove_lock_path "$T/pid-lock" || fail "PID-only legacy lock directory was not removed"
[ ! -e "$T/pid-lock" ] || fail "PID-only lock directory remains"
printf '12345\n' > "$T/file-lock"
_hf_remove_lock_path "$T/file-lock" || fail "canonical file lock was not removed"
[ ! -e "$T/file-lock" ] || fail "canonical file lock remains"

# Unknown and hidden entries are not lock debris and must survive cleanup attempts.
mkdir -p "$T/unknown-lock/nested"
printf '12345\n' > "$T/unknown-lock/pid"
printf 'keep\n' > "$T/unknown-lock/nested/sentinel"
if _hf_remove_lock_path "$T/unknown-lock"; then fail "lock with nested unknown data was removed"; fi
grep -Fqx keep "$T/unknown-lock/nested/sentinel" || fail "nested unknown data was deleted"
[ -s "$T/unknown-lock/pid" ] || fail "PID was removed despite unknown nested data"
mkdir "$T/hidden-lock"
printf '12345\n' > "$T/hidden-lock/pid"
printf 'hidden\n' > "$T/hidden-lock/.keep"
if _hf_remove_lock_path "$T/hidden-lock"; then fail "lock with hidden unknown data was removed"; fi
grep -Fqx hidden "$T/hidden-lock/.keep" || fail "hidden unknown data was deleted"

# A symlinked PID or outer lock directory must be rejected without touching its target.
mkdir "$T/symlink-pid-lock"
printf 'outside\n' > "$T/pid-target"
ln -s "$T/pid-target" "$T/symlink-pid-lock/pid"
if _hf_read_lock_owner "$T/symlink-pid-lock" >/dev/null 2>&1; then fail "PID symlink was followed"; fi
if _hf_remove_lock_path "$T/symlink-pid-lock"; then fail "PID symlink lock was removed"; fi
[ -L "$T/symlink-pid-lock/pid" ] || fail "PID symlink was replaced"
grep -Fqx outside "$T/pid-target" || fail "PID symlink target was modified"
mkdir "$T/outer-target"
printf '12345\n' > "$T/outer-target/pid"
ln -s "$T/outer-target" "$T/outer-link"
if _hf_remove_lock_path "$T/outer-link"; then fail "outer lock symlink was removed"; fi
[ -s "$T/outer-target/pid" ] || fail "outer symlink target lock was modified"

# FIFO PID records must be refused before cat; timeout proves the reader does not block.
command -v mkfifo >/dev/null 2>&1 || fail "mkfifo is required for FIFO lock regression"
command -v timeout >/dev/null 2>&1 || fail "timeout is required for FIFO non-blocking regression"
mkdir "$T/fifo-lock"
mkfifo "$T/fifo-lock/pid"
set +e
timeout 2 sh -c '. "$1"; _hf_read_lock_owner "$2" >/dev/null 2>&1' sh "$HELPERS" "$T/fifo-lock"
fifo_rc=$?
set -e
[ "$fifo_rc" -ne 124 ] || fail "FIFO PID reader blocked instead of rejecting"
[ "$fifo_rc" -ne 0 ] || fail "FIFO PID record was accepted"
if _hf_remove_lock_path "$T/fifo-lock"; then fail "FIFO PID lock directory was removed"; fi
[ -p "$T/fifo-lock/pid" ] || fail "FIFO PID record was removed"

echo "PASS: Hosts cache lock cleanup removes only empty/PID-only locks and refuses FIFO, symlink and unknown contents"
