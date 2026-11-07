#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
service="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java"
runtime="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationRuntime.kt"
scan_throttle="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdPackageScanThrottle.kt"
scan_throttle_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdPackageScanThrottleTest.kt"
pending_scan="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdPendingPackageScan.kt"
pending_scan_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdPendingPackageScanTest.kt"
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
for file in "$service" "$runtime" "$scan_throttle" "$scan_throttle_test" "$pending_scan" "$pending_scan_test" "$snapshot" "$store" "$engine" "$activity" "$main" "$manifest" "$service_xml" "$strings" "$unit"; do
  test -s "$file" || { echo "FAIL: missing GKD single-service integration file: $file"; exit 1; }
done

python3 - "$service" "$runtime" "$scan_throttle" "$scan_throttle_test" "$pending_scan" "$pending_scan_test" "$snapshot" "$store" "$engine" "$activity" "$main" "$manifest" "$service_xml" "$strings" "$unit" <<'PY'
from pathlib import Path
import sys
service, runtime, scan_throttle, scan_throttle_test, pending_scan, pending_scan_test, snapshot, store, engine, activity, main, manifest, service_xml, strings, unit = [
    Path(value).read_text(encoding="utf-8") for value in sys.argv[1:]
]

# One FX AccessibilityService is reused; GKD must not register a parallel service or launcher.
assert "FxGkdAutomationRuntime.process(this, eventPackage, root)" in service
assert "public static void requestReconfigure(Context context)" in service
for event in ("TYPE_WINDOW_STATE_CHANGED", "TYPE_WINDOW_CONTENT_CHANGED", "TYPE_VIEW_SCROLLED"):
    assert event in service, f"FX Accessibility service does not dispatch GKD on {event}"
assert "AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags &= ~AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service, "resource ID permission is not revoked when GKD is disabled"
assert "if (info.eventTypes != wantedEvents || info.flags != wantedFlags)" in service
assert "FxGkdRuleStore.hasEnabledRule(this, pkg)" in service, "service tree access is not gated by per-app opt-in"
assert "AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "wantedFlags &= ~AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS" in service
assert "if (info.eventTypes != wantedEvents || info.flags != wantedFlags)" in service
assert "eventPackage.contentEquals(rootPackage)" in service, "active window package is not matched to the event package"
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
assert "fun isRuleEnabled(context: Context, id: String, packageName: String)" in store, "per-rule package-scoped enable check is missing"
assert "isInstalledUserApplication(service, eventPackage)" in runtime
assert "if (raw == cachedRulesRaw) return cachedRules" in store, "GKD event hot path reparses persisted rules on every event"
assert "cachedRulesRaw = raw" in store and "cachedRules = parsed" in store
write_rules_start = store.index("private fun writeRules(")
write_rules = store[write_rules_start:]
assert "if (committed)" in write_rules
assert "cachedRules = rules.toList()" in write_rules and "cachedRulesRaw = array.toString()" in write_rules
assert "MAX_RULES" not in store, "GKD rule storage must not impose a fixed rule-count ceiling"
assert "MAX_IMPORT_BYTES" not in store, "GKD rule import must not impose a fixed file-size ceiling"
assert 'EXPORT_FORMAT = "FX-GKD-LOCAL-RULES"' in store
assert "EXPORT_SCHEMA_VERSION = 1" in store
assert "fun exportJson(context: Context): String" in store
assert "fun importJson(context: Context, raw: String): FxGkdImportResult" in store
assert "enabled = false" in store, "import must never auto-enable file-provided rules"
assert "isInstalledUserApplication(context, packageName)" in store
assert "规则写入失败，原有规则保持不变。" in store
assert "MIN_COOLDOWN_MS = 1_000L" in store and "MAX_COOLDOWN_MS = 60_000L" in store
assert "FxGkdSelectorEngine.compile(expression)" in store
add_rule_start = store.index("fun addRule(")
add_rule_end = store.index("fun setRuleEnabled(", add_rule_start)
add_rule = store[add_rule_start:add_rule_end]
assert "isInstalledUserApplication(context, pkg)" in add_rule, "manual GKD rule creation accepts missing/system packages"
assert "pkg == context.packageName" in add_rule, "manual GKD rule creation accepts FX itself as a target"

# Snapshot bounds and sensitive text suppression.
for token in ("MAX_NODES = 700", "MAX_DEPTH = 32", "MAX_CHILDREN_PER_NODE = 80",
              "MAX_TEXT_LENGTH = 256", "info.isPassword || info.isEditable",
              "if (sensitive) null"):
    assert token in snapshot, f"Accessibility snapshot bound/privacy guard missing: {token}"

# A platform node can become invalid between traversal and property access.
# Ownership must be registered before any such getter so the failure path can
# recycle the root/current node as well as previously visited descendants.
assert snapshot.index("handles.add(info)") < snapshot.index("val sensitive = info.isPassword || info.isEditable"), \
    "snapshot must own each node before reading potentially throwing platform properties"
assert "for (node in handles.asReversed())" in snapshot and "node.recycle()" in snapshot, \
    "snapshot capture failure must release every node already taken into ownership"

# Runtime is local only, rate-limited, package-scoped and only runs ACTION_CLICK.
for token in ("FxGkdRuleStore.isEnabled(service)", "it.source.packageName == eventPackage",
              "scanThrottle.shouldScan(eventPackage, now)", "now - lastAction < rule.source.cooldownMillis",
              "maximum = 12", "liveNode.isPassword", "liveNode.isEditable",
              "liveNode.isVisibleToUser", "liveNode.isClickable",
              "FxGkdRuleStore.isRuleEnabled(service, rule.source.id, eventPackage)",
              "FxAccessibilityService.isConnected()", "isTargetStillForeground(service, eventPackage)",
              "performAction(AccessibilityNodeInfo.ACTION_CLICK)"):
    assert token in runtime, f"GKD automation guard missing: {token}"
assert "FxGkdPackageScanThrottle(250L)" in runtime, "GKD scan cooldown must be package-scoped"
assert "scanThrottle.retainPackages(cachedCompiled.map { it.source.packageName }.toSet())" in runtime, "removed GKD package cooldown state is not pruned"
assert "scanThrottle.clear()" in runtime, "GKD rule invalidation must clear package scan cooldowns"
assert "gkdPendingScan.request(eventPackage)" in service
assert "gkdPendingScan.complete()" in service
assert "private void startGkdScan(String eventPackage)" in service
assert "private void completeGkdScan()" in service
assert "gkdMainHandler.post" in service
assert "gkdServiceDestroyed = true;" in service and "gkdPendingScan.clear();" in service
assert "AtomicBoolean gkdWorkPending" not in service
for test_name in ("firstRequestStartsAndLatestPendingRunsAfterCompletion",
                  "newestPackageReplacesOlderPendingEvents",
                  "blankPackageDoesNotOccupyTheActiveSlot",
                  "clearDropsPendingPackageAndReleasesSlot"):
    assert test_name in pending_scan_test
assert "latestPendingPackage = requested" in pending_scan
assert "if (next == null) running = false" in pending_scan
assert "lastScanAt" not in runtime, "global scan throttle must not starve other enabled packages"
assert "class FxGkdPackageScanThrottle" in scan_throttle
for test_name in ("cooldownIsIsolatedByTargetPackage", "removedRulePackagesReleaseTheirCooldownState",
                  "invalidationClearsAllPackageCooldowns"):
    assert test_name in scan_throttle_test, f"GKD package throttle unit test missing: {test_name}"
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
              "getInstalledApplications(0)"):
    assert token in activity, f"GKD local rule UI contract missing: {token}"
assert "规则状态保存失败，已恢复原状态。" in activity, "failed per-rule writes must restore the displayed switch state"
assert "规则删除失败，原数据保持不变。" in activity, "failed deletes must not imply success"
assert "body.getChildCount() > 7" in activity, "rule refresh must not remove master, add, import and export controls"
assert "REQUEST_IMPORT_GKD_RULES" in activity and "REQUEST_EXPORT_GKD_RULES" in activity
assert "Intent.ACTION_OPEN_DOCUMENT" in activity and "Intent.ACTION_CREATE_DOCUMENT" in activity
assert "FxGkdRuleStore.importJson(this, json)" in activity
assert "FxGkdRuleStore.exportJson(this)" in activity
assert "所有新导入规则均已关闭" in activity
assert 'setText("启用 GKD 本地规则自动化")' in activity
assert 'setPositiveButton("校验并保存"' in activity
assert "showPackagePicker(EditText packageInput)" in activity
assert "candidates.size() >= 500" not in activity, "app picker must enumerate all installed user apps"
assert "规则状态保存失败，已恢复原状态。" in activity
assert "规则删除失败，原数据保持不变。" in activity

# Versioned local JSON transfer uses the Android document picker without arbitrary file-size caps.
for token in (
    "REQUEST_IMPORT_GKD_RULES", "REQUEST_EXPORT_GKD_RULES",
    "Intent.ACTION_OPEN_DOCUMENT", "Intent.ACTION_CREATE_DOCUMENT",
    'picker.setType("application/json")',
    "FxGkdRuleStore.exportJson(this)",
    "FxGkdRuleStore.importJson(this, json)",
    "FxGkdAutomationRuntime.invalidateRules()",
    "FxAccessibilityService.requestReconfigure(this)",
):
    assert token in activity, f"GKD local JSON transfer UI contract missing: {token}"
assert 'action("导入本地规则", this::openImportRulesPicker)' in activity
assert 'action("导出本地规则", this::openExportRulesPicker)' in activity
assert "所有新导入规则均已关闭" in activity

# Portable rule documents are versioned and merged fail-closed without arbitrary rule-count or file-size caps.
for token in (
    'private const val EXPORT_FORMAT = "FX-GKD-LOCAL-RULES"',
    "private const val EXPORT_SCHEMA_VERSION = 1",
    '.put("format", EXPORT_FORMAT)',
    '.put("schema_version", EXPORT_SCHEMA_VERSION)',
    '.put("rules", exportedRules)',
    '.put("id", rule.id)',
    '.put("package", rule.packageName)',
    '.put("selector", rule.selector)',
    '.put("cooldown_ms", rule.cooldownMillis)',
    '.put("enabled", rule.enabled)',
    'document.optString("format") != EXPORT_FORMAT',
    'document.optInt("schema_version", -1) != EXPORT_SCHEMA_VERSION',
    "isInstalledUserApplication(context, packageName)",
    "FxGkdSelectorEngine.compile(selector).isValid",
    "known.add(packageName +",
    "enabled = false",
    "writeRules(context, merged)",
    "规则写入失败，原有规则保持不变。",
):
    assert token in store, f"safe GKD JSON transfer contract missing: {token}"
assert r"\u0000" in store, "package-selector deduplication must use an unambiguous separator"
import_start = store.index("fun importJson(context: Context, raw: String)")
import_end = store.index("private fun isInstalledUserApplication", import_start)
import_body = store[import_start:import_end]
assert "MAX_IMPORT_BYTES" not in import_body
assert import_body.index("schema_version") < import_body.index("getRules(context)")
assert import_body.index("enabled = false") < import_body.index("writeRules(context, merged)")
assert "setEnabled(context, true)" not in import_body, "importing a document must never enable the GKD master switch"
assert "putBoolean(KEY_MASTER_ENABLED, true)" not in import_body, "import must not activate local automation"

# Capability declaration is transparent and gesture dispatch stays disabled.
assert 'android:canRetrieveWindowContent="true"' in service_xml
assert 'android:canPerformGestures="false"' in service_xml
assert 'android:accessibilityEventTypes="typeWindowStateChanged"' in service_xml
assert "只有用户在 FX 的 GKD 页面主动启用总开关" in strings
assert "限额 Accessibility 节点快照、本地规则匹配与 Click 执行" in activity
assert "尚未接入：上游订阅源、AI 服务商、触发历史、云同步与上游备份格式、复杂动作与手势" in activity

# Upstream parser adapter behavior is exercised on the FX node model.
for test_name in ("matchesUpstreamAttributeAndWidgetSelectors",
                  "rejectsInvalidSelectorSyntaxAndUnknownProperties",
                  "respectsSelectorResultLimit"):
    assert test_name in unit, f"GKD engine unit test missing: {test_name}"
print("PASS: GKD local rules run through the single FX AccessibilityService with opt-in, exact app scope, bounded privacy-preserving snapshots, cooldown, and regression coverage.")
PY
