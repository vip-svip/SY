#!/usr/bin/env python3
"""Fix bundled Hook regressions for the unified dual-entry APK."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
test = root / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh"
if not test.is_file():
    raise SystemExit("FX Hook APK regression test is missing")
src = test.read_text(encoding="utf-8")
old = 'DEXSTR=$(for dex in classes.dex classes2.dex classes3.dex; do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)'
new = 'DEXSTR=$(for dex in $(unzip -Z1 "$APK" | grep -E \'^classes([0-9]+)?[.]dex$\'); do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)'
if old in src:
    src = src.replace(old, new, 1)
elif new not in src:
    raise SystemExit("DEX scan line does not match known regression-test versions")

# Avoid SIGPIPE noise from repeatedly piping a large DEX string into grep -q.
if 'DEXSTR_FILE=$(mktemp)' not in src:
    src = src.replace(
        new,
        new + """\nDEXSTR_FILE=$(mktemp)
printf '%s\\n' "$DEXSTR" > "$DEXSTR_FILE"
trap 'rm -f "$DEXSTR_FILE"' EXIT""",
        1,
    )
old_grep = 'printf \'%s\' "$DEXSTR" | grep -q "$token" || fail "compiled hook marker missing: $token"'
new_grep = 'grep -Fq "$token" "$DEXSTR_FILE" || fail "compiled hook marker missing: $token"'
if old_grep in src:
    src = src.replace(old_grep, new_grep, 1)
elif new_grep not in src:
    raise SystemExit("DEX marker scan does not match known regression-test versions")
old_marker = '"auto member candidate hook installed="'
new_marker = '"auto member candidate hooks installed="'
if old_marker in src:
    src = src.replace(old_marker, new_marker, 1)
elif new_marker not in src:
    raise SystemExit("member candidate log marker does not match known source versions")
test.write_text(src, encoding="utf-8")

# The unified build intentionally removed the split FXAdHook artifact. Keep the
# target-scope integration test aligned with the one-APK build metadata.
scope_test = root / "scripts/tests/v1.0.0-lsposed-ad-hook-target-scope-regression.sh"
if scope_test.is_file():
    scope = scope_test.read_text(encoding="utf-8")
    scope = scope.replace("optional/FXAdHook-BUILD-INFO.txt", "optional/FXUnifiedHook-BUILD-INFO.txt")
    scope = scope.replace(
        "grep -q 'LSPosed API 101' \"$ROOT/optional/FXUnifiedHook-BUILD-INFO.txt\" || fail \"modern API provenance missing\"",
        "grep -Fq 'Dual entrypoints: legacy Xposed API 93+ and modern libxposed API 101' \"$ROOT/optional/FXUnifiedHook-BUILD-INFO.txt\" || fail \"unified Hook API provenance missing\""
    )
    if "optional/FXAdHook-BUILD-INFO.txt" in scope or "LSPosed API 101" in scope:
        raise SystemExit("target-scope regression still references obsolete split-APK metadata")
    scope_test.write_text(scope, encoding="utf-8")
print("Updated unified Hook APK and target-scope regression assertions.")
