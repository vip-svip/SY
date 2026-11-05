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

print("PASS: APK and KernelSU packaging both apply the reviewed subfetch lock patch and run concurrency/stale-lock regressions")
