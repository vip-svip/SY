#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
python3 - "$SRC" <<'PY'
import pathlib, re, sys
src = pathlib.Path(sys.argv[1]).read_text()
needle = r'if\s*\(!privacyEnabled\s*\|\|\s*processPackages\.size\(\)\s*!=\s*1\s*\|\|\s*activeTarget\s*==\s*null\s*\|\|\s*!activeTarget\.privacy\s*\|\|\s*NEVER\.contains\(activePackage\)\)\s*return\s+original\s*;'
if not re.search(needle, src, re.S):
    raise SystemExit("FAIL: Android ID hook must fail open for shared-package processes")
if src.count('chain.proceed()') < 1:
    raise SystemExit("FAIL: original Android ID getter must remain reachable")
print("PASS: Android ID privacy hook fails open for shared-package processes")
PY
