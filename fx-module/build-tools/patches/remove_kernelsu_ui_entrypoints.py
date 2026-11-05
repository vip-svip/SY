#!/usr/bin/env python3
"""Remove KernelSU's module WebUI and manual action entry from the final FX package.

The complete compatible WebUI is embedded in the FX APK. KernelSU remains the
module installer/privileged backend only; it must not expose a second UI or
manual action button.
"""
from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
webroot = root / "webroot"
action = root / "action.sh"

if webroot.exists():
    if not webroot.is_dir():
        raise SystemExit("refusing to remove non-directory webroot")
    shutil.rmtree(webroot)
if action.exists():
    if not action.is_file() or action.is_symlink():
        raise SystemExit("refusing to remove unexpected action.sh entry")
    action.unlink()

if webroot.exists() or action.exists():
    raise SystemExit("KernelSU UI/action entrypoint remains")
print("PASS: final module has no KernelSU WebUI or manual action entry")
