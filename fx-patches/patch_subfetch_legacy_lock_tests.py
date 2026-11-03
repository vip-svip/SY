#!/usr/bin/env python3
"""Update restored-release stale-lock tests for the new POSIX file lock.

The runtime accepts an old PID-bearing directory lock during upgrade, but all
new lock acquisitions are regular private files. These tests intentionally start
with the legacy directory shape and verify safe migration to the new lock.
"""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")

def rewrite(path: Path, marker: str, start_token: str, end_token: str, block: str) -> None:
    if not path.is_file():
        raise SystemExit(f"restored stale-lock test missing: {path}")
    source = path.read_text(encoding="utf-8")
    if marker in source:
        return
    start = source.find(start_token)
    end = source.find(end_token, start + len(start_token)) if start >= 0 else -1
    if start < 0 or end < 0:
        raise SystemExit(f"{path}: stale-lock test section anchors missing; refusing partial rewrite")
    source = source[:start] + block + source[end:]
    old_final = '[ ! -d "$T/state/subs/.lock.$key" ]'
    new_final = '[ ! -e "$T/state/subs/.lock.$key" ] && [ ! -L "$T/state/subs/.lock.$key" ]'
    if source.count(old_final) != 1:
        raise SystemExit(f"{path}: expected one old lock-finalization assertion")
    source = source.replace(old_final, new_final, 1)
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)

ownership = module / "scripts/tests/v1.0.0-subfetch-stale-lock-ownership-regression.sh"
ownership_block = '''# FX_SUBFETCH_LEGACY_DIR_COMPAT_V1
# New locks are private atomic files; stale legacy PID directories remain
# readable only via the owner helper and are renamed as a whole.
grep -Fq 'FX_SUBFETCH_FILE_LOCK_V2' "$F"
grep -Fq '_sl_read_lock_owner "$LOCK"' "$F"
grep -Fq '_sl_stale="$LOCK.stale.$$.$_sl_try"' "$F"
grep -Fq 'mv "$LOCK" "$_sl_stale" 2>/dev/null; then' "$F"
grep -Fq '_sl_moved_owner=$(_sl_read_lock_owner "$_sl_stale"' "$F"
grep -Fq '[ "$_sl_moved_owner" = "$_sl_owner" ]' "$F"
if grep -Fq 'rm -f "$LOCK/pid"' "$F" || grep -Fq 'rmdir "$LOCK"' "$F"; then
  echo 'FAIL: stale lock reaper still performs non-atomic legacy PID cleanup' >&2
  exit 1
fi
'''
rewrite(
    ownership,
    "FX_SUBFETCH_LEGACY_DIR_COMPAT_V1",
    "# Static guard:",
    'T=$(mktemp',
    ownership_block,
)

reclaim = module / "scripts/tests/v1.0.0-subfetch-stale-lock-reclaim-regression.sh"
reclaim_block = '''# FX_SUBFETCH_LEGACY_DIR_COMPAT_V1
# New lock files use O_EXCL/noclobber; legacy PID directories are read only
# through the owner helper and quarantined via an atomic rename.
grep -Fq 'FX_SUBFETCH_FILE_LOCK_V2' "$F"
grep -Fq '_sl_stale="$LOCK.stale.$$.$_sl_try"' "$F"
grep -Fq 'mv "$LOCK" "$_sl_stale" 2>/dev/null; then' "$F"
grep -Fq '_sl_moved_owner=$(_sl_read_lock_owner "$_sl_stale"' "$F"
grep -Fq '[ "$_sl_moved_owner" = "$_sl_owner" ]' "$F"
if grep -Fq 'mv "$_sl_stale" "$LOCK"' "$F"; then
  echo 'FAIL: quarantine restore can overwrite a replacement lock' >&2
  exit 1
fi
if grep -Fq 'rm -f "$LOCK/pid"' "$F" || grep -Fq 'rmdir "$LOCK"' "$F"; then
  echo 'FAIL: stale-lock reaper can delete a replacement lock' >&2
  exit 1
fi
'''
rewrite(
    reclaim,
    "FX_SUBFETCH_LEGACY_DIR_COMPAT_V1",
    "# Stale lock reclamation",
    "# Exercise the real script",
    reclaim_block,
)
print("Updated restored stale-lock tests for legacy directory compatibility and atomic file locks.")
