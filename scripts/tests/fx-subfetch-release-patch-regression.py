#!/usr/bin/env python3
"""Verify the KernelSU Release restore applies the reviewed subfetch lock migration."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
LOCK_PATCHER = ROOT / "fx-patches/patch_subfetch_file_lock.py"
LEGACY_PATCHER = ROOT / "fx-patches/patch_subfetch_legacy_lock_tests.py"
WORKFLOW = ROOT / ".github/workflows/build-fx-kernelsu.yml"

def run(*args: str) -> None:
    subprocess.run(args, check=True, cwd=ROOT, stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, text=True)

with tempfile.TemporaryDirectory(prefix="fx-subfetch-patch-") as temporary:
    module = Path(temporary) / "fx-module"
    scripts = module / "scripts"
    tests = scripts / "tests"
    tests.mkdir(parents=True)
    subfetch = scripts / "subfetch.sh"
    subfetch.write_text(
        '#!/system/bin/sh\n'
        'LOCK="$SUBDIR/.lock.$_key"\n'
        '# 只有显式 --local 才允许「没缓存就报错」\n',
        encoding="utf-8",
    )
    subfetch.chmod(0o755)

    run("python3", str(LOCK_PATCHER), str(module))
    migrated = subfetch.read_text(encoding="utf-8")
    assert migrated.count("FX_SUBFETCH_FILE_LOCK_V2") == 1
    assert 'set -C; printf' in migrated
    assert 'trap \'subfetch_unlock\' 0' in migrated
    assert '_sl_read_lock_owner' in migrated
    assert '_sl_stale="$LOCK.stale.$$.$_sl_try"' in migrated
    first_digest = hashlib.sha256(migrated.encode()).hexdigest()

    run("python3", str(LOCK_PATCHER), str(module))
    second = subfetch.read_text(encoding="utf-8")
    assert hashlib.sha256(second.encode()).hexdigest() == first_digest,         "subfetch lock patcher must be idempotent"
    run("sh", "-n", str(subfetch))

    run("python3", str(LEGACY_PATCHER), str(module))
    ownership = tests / "v1.0.0-subfetch-stale-lock-ownership-regression.sh"
    reclaim = tests / "v1.0.0-subfetch-stale-lock-reclaim-regression.sh"
    for script in (ownership, reclaim):
        assert script.is_file() and script.stat().st_mode & 0o111
        text = script.read_text(encoding="utf-8")
        assert "FX_SUBFETCH_LEGACY_DIR_COMPAT_V1" in text
        assert 'mv "$LOCK" "$_sl_stale"' in text
        assert 'mv "$_sl_stale" "$LOCK"' not in text
        run("sh", "-n", str(script))
        digest = hashlib.sha256(text.encode()).hexdigest()
        run("python3", str(LEGACY_PATCHER), str(module))
        assert hashlib.sha256(script.read_bytes()).hexdigest() == digest,             "legacy stale-lock test generation must be idempotent"

workflow = WORKFLOW.read_text(encoding="utf-8")
lock_patch = workflow.index("python3 fx-patches/patch_subfetch_file_lock.py fx-module")
legacy_patch = workflow.index("python3 fx-patches/patch_subfetch_legacy_lock_tests.py fx-module")
fixture_copy = workflow.index(
    "install -D -m 0755 scripts/tests/v1.0.0-subfetch-concurrency-regression.sh "
    "fx-module/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh"
)
concurrency_run = workflow.index(
    "sh fx-module/scripts/tests/v1.0.0-subfetch-concurrency-regression.sh",
    fixture_copy,
)
ownership_run = workflow.index(
    "sh fx-module/scripts/tests/v1.0.0-subfetch-stale-lock-ownership-regression.sh",
    concurrency_run,
)
reclaim_run = workflow.index(
    "sh fx-module/scripts/tests/v1.0.0-subfetch-stale-lock-reclaim-regression.sh",
    ownership_run,
)
full_suite = workflow.index("find fx-module/scripts/tests -maxdepth 1 -type f -name '*.sh'")
assert lock_patch < legacy_patch < fixture_copy < concurrency_run < ownership_run < reclaim_run < full_suite,     "KernelSU restore must patch the release source and execute the subfetch tests before the full module suite"

print("PASS: restored subfetch file-lock migration, idempotent stale-lock test generation, and KernelSU package wiring")
