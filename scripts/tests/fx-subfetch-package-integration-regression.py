#!/usr/bin/env python3
"""Keep restored Release modules on the same subscription lock protocol in both build paths."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = (
    ROOT / ".github/workflows/build-fx-adhook.yml",
    ROOT / ".github/workflows/build-fx-kernelsu.yml",
)

for workflow_path in WORKFLOWS:
    text = workflow_path.read_text(encoding="utf-8")
    patch_lock = "python3 fx-patches/patch_subfetch_file_lock.py fx-module"
    patch_tests = "python3 fx-patches/patch_subfetch_legacy_lock_tests.py fx-module"
    concurrency = "sh fx-module/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
    stale_owner = "sh fx-module/scripts/tests/v1.0.0-subfetch-stale-lock-ownership-regression.sh"
    stale_reclaim = "sh fx-module/scripts/tests/v1.0.0-subfetch-stale-lock-reclaim-regression.sh"
    for token in (patch_lock, patch_tests, concurrency, stale_owner, stale_reclaim):
        assert token in text, f"{workflow_path.name}: missing {token}"
    assert text.index(patch_lock) < text.index(patch_tests) < text.index(concurrency), (
        f"{workflow_path.name}: patch the Release module before testing concurrency"
    )
    assert text.index(concurrency) < text.index(stale_owner) < text.index(stale_reclaim), (
        f"{workflow_path.name}: run the concurrency and both stale-lock scenarios in order"
    )
    assert "patch_subfetch_file_lock.py fx-module" in text
    assert "patch_subfetch_legacy_lock_tests.py fx-module" in text

# A legacy lock directory is removable only after verifying its sole ordinary PID file.
patcher = (ROOT / "fx-patches/patch_subfetch_file_lock.py").read_text(encoding="utf-8")
read_owner = patcher[patcher.index("_sl_read_lock_owner() {"):patcher.index("_sl_remove_owned_lock_path() {")]
remove_lock = patcher[patcher.index("_sl_remove_owned_lock_path() {"):patcher.index("subfetch_unlock() {")]
assert '[ -f "$_sl_path/pid" ]' in read_owner and '[ ! -L "$_sl_path/pid" ]' in read_owner
assert '[ -f "$_sl_path/pid" ]' in remove_lock and '[ ! -L "$_sl_path/pid" ]' in remove_lock
assert "for _sl_entry in " in remove_lock and '[ "$_sl_entry" = "$_sl_path/pid" ] || return 1' in remove_lock
assert 'rmdir "$_sl_path"' in remove_lock and 'rm -rf "$_sl_path"' not in remove_lock
assert 'rm -rf "$_sl_path"' not in patcher

generator = (ROOT / "fx-patches/patch_subfetch_legacy_lock_tests.py").read_text(encoding="utf-8")
for marker in ("unknown-directory", ".sentinel", "mkfifo", "timeout 2", "symlink-pid-directory", "fifo-directory"):
    assert marker in generator, f"generated lock safety regression missing {marker}"
escaped_tmpdir = chr(92) + "$" + "{TMPDIR"
assert escaped_tmpdir not in generator, "generated stale-lock fixtures must expand TMPDIR"

print("PASS: APK and KernelSU subscription lock patch and safety regression contracts")
