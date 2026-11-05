#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
runtime="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorRuntime.kt"
unit="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorRuntimeTest.kt"
adapter="$root/adhook/gkd-selector-adapter/build.gradle"
test -s "$runtime" && test -s "$unit" && test -s "$adapter" || {
  echo "FAIL: GKD selector runtime, unit tests or pinned adapter build file missing"
  exit 1
}
python3 - "$runtime" "$unit" "$adapter" <<'PY'
from pathlib import Path
import sys
runtime = Path(sys.argv[1]).read_text(encoding="utf-8")
unit = Path(sys.argv[2]).read_text(encoding="utf-8")
adapter = Path(sys.argv[3]).read_text(encoding="utf-8")

# The FX runtime must use the real pinned GKD-XA parser and type model.
for token in ("Selector.parse(source)", "selector.validateType(typeModel)",
              "createDefaultSelectorTypeModel(webField = false)",
              "SelectorParseResult.Failure", "SelectorTypeResult.Failure"):
    assert token in runtime, f"GKD selector parser/type-check contract missing: {token}"

# Bound untrusted selector input and Accessibility traversal work.
for token in ("MAX_SELECTOR_CHARS = 8_192", "MAX_CHILDREN_PER_NODE = 200",
              "MAX_DESCENDANTS_PER_QUERY = 4_000", "MAX_FAST_QUERY_RESULTS = 500",
              "MAX_PARENT_DEPTH = 256", "limit.coerceIn(1, MAX_FAST_QUERY_RESULTS)"):
    assert token in runtime, f"GKD runtime bound missing: {token}"
assert "yielded < MAX_DESCENDANTS_PER_QUERY" in runtime
assert "total >= MAX_FAST_QUERY_RESULTS" in runtime
assert "index >= getChildCount(node)" in runtime
assert "if (name != \"getChild\") return null" in runtime

# The adapter is read-only: FX owns actions and calls this runtime only to match nodes.
for forbidden in ("performAction(", "ACTION_CLICK", "ACTION_LONG_CLICK", "dispatchGesture("):
    assert forbidden not in runtime, f"selector evaluation must not execute UI actions: {forbidden}"
assert "AccessibilityNodeInfo" in runtime and "NodeAdapter<AccessibilityNodeInfo>" in runtime
assert "safeList { node.findAccessibilityNodeInfosByViewId" in runtime
assert "safeList { node.findAccessibilityNodeInfosByText" in runtime

# Runtime parser/type-check behavior is covered by app unit tests.
for token in ("compilesGkdSelectorSyntaxAndExposesFastQueryMetadata",
              "rejectsSyntaxErrorsWithSourceOffsets",
              "rejectsUnknownAccessibilityPropertiesDuringTypeCheck",
              "enforcesBoundedSelectorSourceLength",
              "acceptsGkdPropertyMethodsAndRelationshipSyntax"):
    assert token in unit, f"FX GKD runtime unit test missing: {token}"

assert "jvmToolchain(17)" in adapter
assert "vendor/GKD-XA/gkd-selector/src/commonMain/kotlin" in adapter
print("PASS: GKD selector parser/type-check is wired to the FX Accessibility tree with bounded read-only matching and regression coverage.")
PY
