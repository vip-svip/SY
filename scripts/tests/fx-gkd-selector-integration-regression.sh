#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
module="$root/adhook/fx-gkd-selector/build.gradle"
engine="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorEngine.kt"
unit="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorEngineTest.kt"
store="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt"
automation="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationRuntime.kt"
snapshot="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAccessibilitySnapshot.kt"
service="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java"
app_build="$root/adhook/app/build.gradle"
settings="$root/adhook/settings.gradle"
root_build="$root/adhook/build.gradle"
readme="$root/adhook/fx-gkd-selector/README.md"
plan="$root/docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md"
for file in "$module" "$engine" "$unit" "$store" "$automation" "$snapshot" "$service" "$app_build" "$settings" "$root_build" "$readme" "$plan"; do
  test -s "$file" || { echo "FAIL: missing GKD single-runtime integration file: $file"; exit 1; }
done

grep -Fq "id 'org.jetbrains.kotlin.multiplatform' version '2.4.21' apply false" "$root_build"
grep -Fq "include ':app', ':fx-gkd-selector'" "$settings"
grep -Fq "implementation project(':fx-gkd-selector')" "$app_build"
grep -Fq "commonMain/kotlin" "$module"
grep -Fq "jvmMain/kotlin" "$module"
grep -Fq "commonTest/kotlin" "$module"
grep -Fq "jvmTest/kotlin" "$module"
grep -Fq "vendor/GKD-XA/gkd-selector/src" "$module"
! grep -Eq 'gkd-selector-adapter|project\(\x27:gkd-selector\x27\)|project\(\x27:gkd-app\x27\)' "$app_build" "$settings"

grep -Fq "Selector.compile(normalized)" "$engine"
grep -Fq "selector.validateType(typeModel)" "$engine"
grep -Fq "querySelectorAll(root, selector" "$engine"
grep -Fq "matches.take(maximum)" "$engine"
grep -Fq "MAX_RULES = 128" "$store"
grep -Fq "getBoolean(KEY_MASTER_ENABLED, false)" "$store"
grep -Fq "FxGkdSelectorEngine.compile(expression)" "$store"
grep -Fq "FxGkdRuleStore.isEnabled(service)" "$automation"
grep -Fq "it.source.packageName == eventPackage" "$automation"
grep -Fq "liveNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)" "$automation"
grep -Fq "MAX_NODES = 700" "$snapshot"
grep -Fq "MAX_DEPTH = 32" "$snapshot"
grep -Fq "info.isPassword || info.isEditable" "$snapshot"
grep -Fq "FxGkdAutomationRuntime.process(this, pkg, root)" "$service"
grep -Fq "FxGkdRuleStore.hasEnabledRule(this, pkg)" "$service"
grep -Fq "matchesUpstreamAttributeAndWidgetSelectors" "$unit"
grep -Fq "respectsSelectorResultLimit" "$unit"
grep -Fq "GPL-3.0" "$readme"

manifest="$root/adhook/app/src/main/AndroidManifest.xml"
test -s "$manifest"
test "$(grep -Fc 'android:name=".FxAccessibilityService"' "$manifest")" -eq 1
test "$(grep -Fc 'android:name=".FxGkdAutomationActivity" android:exported="false"' "$manifest")" -eq 1
test "$(grep -Fc 'android.intent.category.LAUNCHER' "$manifest")" -eq 1
! grep -Eq 'li\.gkd\.app|gkd\.service\.|gkd\.app\.service|GkdTileService|A11yService' "$manifest" || {
  echo "FAIL: GKD-XA second app/service identity must not be copied into FX Manifest"
  exit 1
}
echo "PASS: one pinned GKD selector module, one FX engine/store/snapshot/runtime, local opt-in rules and the existing single AccessibilityService are wired."
