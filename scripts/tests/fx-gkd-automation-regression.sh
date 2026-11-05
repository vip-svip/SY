#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
service="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java"
runtime="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationRuntime.kt"
snapshot="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAccessibilitySnapshot.kt"
store="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt"
engine="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorEngine.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationActivity.java"
main="$root/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
manifest="$root/adhook/app/src/main/AndroidManifest.xml"
test "$#" -eq 0
for file in "$service" "$runtime" "$snapshot" "$store" "$engine" "$activity" "$main" "$manifest"; do
  test -s "$file" || { echo "FAIL: missing GKD single-service integration file: $file"; exit 1; }
done

python3 - "$service" "$runtime" "$snapshot" "$store" "$engine" "$activity" "$main" "$manifest" <<'PY'
from pathlib import Path
import sys
service, runtime, snapshot, store, engine, activity, main, manifest = [
    Path(value).read_text(encoding="utf-8") for value in sys.argv[1:]
]

# There must be one FX AccessibilityService; GKD reuses it, it does not declare another.
assert "FxGkdAutomationRuntime.process(this, pkg, root)" in service
assert "public static void requestReconfigure(Context context)" in service
for event in ("TYPE_WINDOW_STATE_CHANGED", "TYPE_WINDOW_CONTENT_CHANGED", "TYPE_VIEW_SCROLLED"):
    assert event in service, f"FX Accessibility service does not dispatch GKD on {event}"
assert "FxGkdRuleStore.hasEnabledRule(this, pkg)" in service
assert "root.getPackageName()" in service and "pkg.equals(rootPackage.toString())" in service
assert "getRootInActiveWindow()" in service
assert 'android:name=".FxAccessibilityService"' in manifest
assert manifest.count('android:name=".FxAccessibilityService"') == 1
assert 'android:name=".FxGkdAutomationActivity" android:exported="false"' in manifest
assert not any(token in manifest for token in ("gkd.app.App", "gkd.service.", "GkdA11yService"))

# Explicit opt-in and app-scoped rules are required before the existing service reads a tree.
assert 'getBoolean(KEY_MASTER_ENABLED, false)' in store
assert "it.enabled && it.packageName == packageName" in store
assert "MAX_RULES = 128" in store
assert "MIN_COOLDOWN_MS = 1_000L" in store and "MAX_COOLDOWN_MS = 60_000L" in store
assert "FxGkdSelectorEngine.compile(expression)" in store

# Matching/action safety: bounded snapshot, sensitive text suppression, package scoping,
# one action per event and a per-rule cooldown. No remote traffic or text logging.
for token in ("MAX_NODES = 700", "MAX_DEPTH = 32", "MAX_CHILDREN_PER_NODE = 80",
              "MAX_TEXT_LENGTH = 256", "info.isPassword || info.isEditable",
              "if (sensitive) null"):
    assert token in snapshot, f"Accessibility snapshot bound/privacy guard missing: {token}"
for token in ("FxGkdRuleStore.isEnabled(service)", "it.source.packageName == eventPackage",
              "now - lastScanAt < 250L", "now - lastAction < rule.source.cooldownMillis",
              "maximum = 12", "liveNode.isPassword", "liveNode.isEditable",
              "liveNode.isVisibleToUser", "liveNode.isClickable",
              "performAction(AccessibilityNodeInfo.ACTION_CLICK)"):
    assert token in runtime, f"GKD automation guard missing: {token}"
assert "screenshot" in runtime.lower() and "network calls" in runtime.lower()

# User can reach the local rule manager from Hook, inspect service permission,
# create a package-scoped selector and control the master/per-rule switches.
assert 'addNativeActionCard("GKD 辅助自动化"' in main
assert "FxGkdAutomationActivity.class" in main
for token in ("FxGkdRuleStore.isEnabled(this)", "FxGkdRuleStore.setEnabled(this, checked)",
              "FxGkdRuleStore.addRule(", "isInstalledUserApplication(pkg)",
              "FxGkdRuleStore.setRuleEnabled(", "FxGkdRuleStore.removeRule("):
    assert token in activity, f"GKD local rule UI contract missing: {token}"
assert 'setText("启用 GKD 本地规则自动化")' in activity
assert 'setPositiveButton("校验并保存"' in activity
print("PASS: GKD local rules are exposed in Hook and dispatched through the single FX AccessibilityService with explicit opt-in, exact package scope, bounded privacy-preserving snapshots and cooldown.")
PY
