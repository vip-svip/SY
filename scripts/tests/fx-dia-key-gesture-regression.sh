#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
DIA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
POLICY="$DIA/FxDiaKeyGesturePolicy.java"
REGISTRY="$DIA/FxDiaKeyGesturePolicyRegistry.java"
HOST="$ROOT/scripts/tests/FxDiaKeyGesturePolicyHostTest.java"
fail() { echo "FAIL: $*" >&2; exit 1; }
for file in "$HOOK" "$POLICY" "$REGISTRY" "$HOST"; do
    [ -s "$file" ] || fail "missing ActivityKey source: $file"
done
python3 - "$HOOK" <<'PY'
from pathlib import Path
import sys
hook = Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    "private final FxDiaKeyGesturePolicyRegistry diaKeyGesturePolicies",
    "diaKeyGesturePolicies.forPackage(pkg);",
    "diaKeyGesturePolicies.remove(pkg);",
    "diaKeyGesturePolicies.forPackage(packageName);",
    'Activity.class.getDeclaredMethod("dispatchKeyEvent", KeyEvent.class)',
    'Activity.class.getDeclaredMethod("onKeyLongPress",',
    "gesturePolicy.onKeyDown(",
    "gesturePolicy.onLongPress(",
    "return chain.proceed();",
    "final boolean systemTarget = (applicationFlags & (ApplicationInfo.FLAG_SYSTEM",
)
for item in required:
    if item not in hook:
        raise SystemExit("FAIL: ActivityKey runtime contract missing: " + item)
if "private final FxDiaKeyGesturePolicy diaKeyGesturePolicy =" in hook:
    raise SystemExit("FAIL: ActivityKey still uses one process-global gesture decoder")
print("PASS: ActivityKey package-scoped LSPosed hook wiring")
PY
command -v javac >/dev/null 2>&1 || fail "JDK is required"
command -v java >/dev/null 2>&1 || fail "JRE is required"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
javac -Xlint:all -Werror -d "$OUT" "$POLICY" "$REGISTRY" "$HOST"
java -cp "$OUT" de.privacyguard.adhook.imported.dia.FxDiaKeyGesturePolicyHostTest
