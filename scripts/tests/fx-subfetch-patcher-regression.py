#!/usr/bin/env python3
"""Regression: repair a restored V2 subscription lock with truncated PID expansion."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_subfetch_file_lock.py"
assert PATCHER.is_file(), "subscription lock patcher is missing"

fixture = """#!/bin/sh
LOCK="$SUBDIR/.lock.$_key"
# FX_SUBFETCH_FILE_LOCK_V2
subfetch_unlock() {
  _sl_release_owner=$(_sl_read_lock_owner "$_sl_release" 2>/dev/null || :)
  if [ "$_sl_release_owner" = "$" ]; then
    rm -f "$_sl_release"
  fi
}
# 只有显式 --local 才允许「没缓存就报错」
"""

with tempfile.TemporaryDirectory(prefix="fx-subfetch-patcher-") as temp:
    module = Path(temp) / "module"
    scripts = module / "scripts"
    scripts.mkdir(parents=True)
    target = scripts / "subfetch.sh"
    target.write_text(fixture, encoding="utf-8")

    first = subprocess.run(
        [sys.executable, str(PATCHER), str(module)],
        check=False,
        text=True,
        capture_output=True,
    )
    assert first.returncode == 0, first.stdout + first.stderr
    repaired = target.read_text(encoding="utf-8")
    required = (
        'if [ "$_sl_release_owner" = "$$" ]; then',
        '_sl_release="$LOCK.release.$$"',
        '_sl_stale="$LOCK.stale.$$.$_sl_try"',
        'if [ "$_sl_again" = "$_sl_owner" ]; then',
        'if [ "$_sl_moved_owner" = "$_sl_owner" ]',
        "trap 'subfetch_unlock' 0",
    )
    for token in required:
        assert token in repaired, f"repaired V2 lock is missing: {token}"
    assert 'if [ "$_sl_release_owner" = "$" ]; then' not in repaired, \
        "truncated PID expansion survived the lock repair"

    snapshot = repaired
    second = subprocess.run(
        [sys.executable, str(PATCHER), str(module)],
        check=False,
        text=True,
        capture_output=True,
    )
    assert second.returncode == 0, second.stdout + second.stderr
    assert target.read_text(encoding="utf-8") == snapshot, \
        "complete V2 lock patch must be idempotent"

print("PASS: incomplete V2 subscription lock is repaired and complete lock patch is idempotent")
