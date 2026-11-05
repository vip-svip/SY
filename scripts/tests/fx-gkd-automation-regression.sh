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
service_xml="$root/adhook/app/src/main/res/xml/fx_accessibility_service.xml"
strings="$root/adhook/app/src/main/res/values/fx_strings.xml"
unit="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorEngineTest.kt"
test "$#" -eq 0
for file in "$service" "$runtime" "$snapshot" "$store" "$engine" "$activity" "$main" "$manifest" "$service_xml" "$strings" "$unit"; do
  test -s "$file" || { echo "FAIL: missing GKD single-service integration file: $file"; exit 1; }
done

python3 - "$service" "$runtime" "$snapshot" "$store" "$engine" "$activity" "$main" "$manifest" "$service_xml" "$strings" "$unit" <<'PY'
from pathlib import Path
import sys
service, runtime, snapshot, store, engine, activity, main, manifest, service_xml, strings, unit = [
    Path(value).read_text(encoding="utf-8") for value in sys.argv[1:]
]

# One FX AccessibilityService is reused; GKD must not register a parallel service or launcher.
assert "FxGkdAutomationRuntime.process(this, eventPackage, root)" in service
assert "public static void requestReconfigure(Context context)" in service
for event in ("TYPE_WINDOW_STATE_CHANGED", "TYPE_WINDOW_CONTENT_CHANGED", "TYPE_VIEW_SCROLLED"):
    assert event in service, f"FX Accessibility service does not dispatch GKD on {event}"
assert "AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags &= ~AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "if (info.eventTypes != wantedEvents || info.flags != wantedFlags)" in service
assert "FxGkdRuleStore.hasEnabledRule(this, pkg)" in service
assert "AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags &= ~AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "if (info.eventTypes != wantedEvents || info.flags != wantedFlags)" in service
assert "eventPackage.contentEquals(rootPackage)" in service
assert "getRootInActiveWindow()" in service
assert 'android:name=".FxAccessibilityService"' in manifest
assert manifest.count('android:name=".FxAccessibilityService"') == 1
assert 'android:name=".FxGkdAutomationActivity" android:exported="false"' in manifest
assert manifest.count('android:name=".FxGkdAutomationActivity"') == 1
assert manifest.count('android.intent.category.LAUNCHER') == 1
assert not any(token in manifest for token in ("gkd.app.App", "gkd.service.", "GkdA11yService"))

# The service may read a window tree only after both a master opt-in and an exact
# installed user-app rule have been established.
assert 'getBoolean(KEY_MASTER_ENABLED, false)' in store
assert "it.enabled && it.packageName == packageName" in store
assert "isRuleEnabled(context, id, packageName)" in store
assert "isInstalledUserApplication(service, eventPackage)" in runtime
assert "MAX_RULES = 128" in store
assert "MIN_COOLDOWN_MS = 1_000L" in store and "MAX_COOLDOWN_MS = 60_000L" in store
assert "FxGkdSelectorEngine.compile(expression)" in store

# Snapshot bounds and sensitive text suppression.
for token in ("MAX_NODES = 700", "MAX_DEPTH = 32", "MAX_CHILDREN_PER_NODE = 80",
              "MAX_TEXT_LENGTH = 256", "info.isPassword || info.isEditable",
              "if (sensitive) null"):
    assert token in snapshot, f"Accessibility snapshot bound/privacy guard missing: {token}"

# Runtime is local only, rate-limited, package-scoped and only runs ACTION_CLICK.
for token in ("FxGkdRuleStore.isEnabled(service)", "it.source.packageName == eventPackage",
              "now - lastScanAt < 250L", "now - lastAction < rule.source.cooldownMillis",
              "maximum = 12", "liveNode.isPassword", "liveNode.isEditable",
              "liveNode.isVisibleToUser", "liveNode.isClickable",
              "FxGkdRuleStore.isRuleEnabled(service, rule.source.id, eventPackage)",
              "FxAccessibilityService.isConnected()", "isTargetStillForeground(service, eventPackage)",
              "performAction(AccessibilityNodeInfo.ACTION_CLICK)"):
    assert token in runtime, f"GKD automation guard missing: {token}"
for forbidden in ("dispatchGesture(", "takeScreenshot(", "HttpURLConnection", "OkHttpClient", "ACTION_LONG_CLICK"):
    assert forbidden not in runtime, f"unexpected unscoped GKD capability: {forbidden}"

# Hook page, per-rule UI and six-tab entry.
assert main.count('addNativeActionCard("GKD 选择器自动化"') == 1
assert 'addNativeActionCard("GKD 辅助自动化"' not in main
assert "FxGkdAutomationActivity.class" in main
for token in ("FxGkdRuleStore.isEnabled(this)", "FxGkdRuleStore.setEnabled(this, enabled)",
              "FxGkdRuleStore.addRule(", "isInstalledUserApplication(pkg)",
              "FxGkdRuleStore.setRuleEnabled(", "FxGkdRuleStore.removeRule(",
              "updateMasterEnabled(Switch control, boolean enabled)",
              "updateRuleEnabled(FxGkdRule rule, Switch control, boolean enabled)",
              "showPackagePicker(EditText packageInput)",
              "getInstalledApplications(0)", "candidates.size() >= 500"):
    assert token in activity, f"GKD local rule UI contract missing: {token}"
assert "规则状态保存失败，已恢复原状态。" in activity, "failed per-rule writes must restore the displayed switch state"
assert "规则删除失败，原数据保持不变。" in activity, "failed deletes must not imply success"
assert "body.getChildCount() > 6" in activity, "rule refresh must not remove the master switch/add-rule button"
assert 'setText("启用 GKD 本地规则自动化")' in activity
assert 'setPositiveButton("校验并保存"' in activity
assert "showPackagePicker(EditText packageInput)" in activity
assert "getInstalledApplications(0)" in activity
assert "candidates.size() >= 500" in activity
assert "规则状态保存失败，已恢复原状态。" in activity
assert "规则删除失败，原数据保持不变。" in activity

# Capability declaration is transparent and gesture dispatch stays disabled.
assert 'android:canRetrieveWindowContent="true"' in service_xml
assert 'android:canPerformGestures="false"' in service_xml
assert 'android:accessibilityEventTypes="typeWindowStateChanged"' in service_xml
assert "只有用户在 FX 的 GKD 页面主动启用总开关" in strings
assert "限额 Accessibility 节点快照、本地规则匹配与 Click 执行" in activity
assert "尚未接入：上游订阅源、规则组/排除项、AI 服务商、触发历史、云同步与上游备份格式" in activity

# Upstream parser adapter behavior is exercised on the FX node model.
for test_name in ("matchesUpstreamAttributeAndWidgetSelectors",
                  "rejectsInvalidSelectorSyntaxAndUnknownProperties",
                  "respectsSelectorResultLimit"):
    assert test_name in unit, f"GKD engine unit test missing: {test_name}"
print("PASS: GKD local rules run through the single FX AccessibilityService with opt-in, exact app scope, bounded privacy-preserving snapshots, cooldown, and regression coverage.")
PY
