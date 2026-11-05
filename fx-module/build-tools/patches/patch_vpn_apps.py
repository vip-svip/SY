#!/usr/bin/env python3
"""Restore the reviewed per-app VPN manager after the stable Release overlay."""
from pathlib import Path
import shutil
import subprocess
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
repo = Path(sys.argv[2] if len(sys.argv) > 2 else ".").resolve()
source = repo / "scripts/vpn-apps.sh"
source_test = repo / "scripts/tests/v1.0.0-yulong-per-app-vpn-regression.sh"
target = module / "scripts/vpn-apps.sh"
target_test = module / "scripts/tests/v1.0.0-yulong-per-app-vpn-regression.sh"

for path, minimum in ((source, 5000), (source_test, 2500)):
    if not path.is_file() or path.stat().st_size < minimum:
        raise SystemExit(f"reviewed per-app VPN source missing or unexpectedly small: {path}")

check = subprocess.run(["sh", "-n", str(source)], text=True, capture_output=True)
if check.returncode:
    raise SystemExit("canonical vpn-apps.sh has invalid POSIX syntax:\n" + check.stderr)

target.parent.mkdir(parents=True, exist_ok=True)
target_test.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source, target)
shutil.copy2(source_test, target_test)
target.chmod(0o755)
target_test.chmod(0o755)

check = subprocess.run(["sh", "-n", str(target)], text=True, capture_output=True)
if check.returncode:
    raise SystemExit("restored vpn-apps.sh has invalid POSIX syntax:\n" + check.stderr)
print("PASS: restored canonical POSIX per-app VPN manager and regression")
