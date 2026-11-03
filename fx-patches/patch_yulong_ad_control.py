#!/usr/bin/env python3
"""Stage the native Yulong AdBlock control backend into the restored FX release module."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
repo = Path(sys.argv[2] if len(sys.argv) > 2 else ".").resolve()
source = repo / "fx-module/scripts/yulong-ad-control.sh"
target = module / "scripts/yulong-ad-control.sh"
if not source.is_file() or source.stat().st_size < 7000:
    raise SystemExit("Yulong Ad control backend is missing or incomplete")
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source, target)
target.chmod(0o755)
print("Staged Yulong AdBlock native Root control backend.")
