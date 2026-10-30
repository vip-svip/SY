#!/usr/bin/env python3
"""Fix the bundled FXAdHook regression to inspect every multidex entry."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
test = root / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh"
if not test.is_file():
    raise SystemExit("FXAdHook APK regression test is missing")
src = test.read_text(encoding="utf-8")
old = 'DEXSTR=$(for dex in classes.dex classes2.dex classes3.dex; do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)'
new = 'DEXSTR=$(for dex in $(unzip -Z1 "$APK" | grep -E \'^classes([0-9]+)?[.]dex$\'); do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)'
if old in src:
    src = src.replace(old, new, 1)
elif new not in src:
    raise SystemExit("DEX scan line does not match known regression-test versions")
test.write_text(src, encoding="utf-8")
print("Updated FXAdHook regression to scan all DEX files.")
