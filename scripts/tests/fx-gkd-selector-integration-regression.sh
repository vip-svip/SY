#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
module="$root/adhook/fx-gkd-selector/build.gradle"
engine="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorEngine.kt"
snapshot="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAccessibilitySnapshot.kt"
automation="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationRuntime.kt"
rules="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt"
unit="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorEngineTest.kt"
app_build="$root/adhook/app/build.gradle"
settings="$root/adhook/settings.gradle"
root_build="$root/adhook/build.gradle"
plan="$root/docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md"

for file in "$module" "$engine" "$snapshot" "$automation" "$rules" "$unit" "$app_build" "$settings" "$root_build" "$plan"; do
  test -s "$file" || { echo "FAIL: missing GKD selector integration file: $file"; exit 1; }
done

grep -Fq "id 'org.jetbrains.kotlin.multiplatform' version '2.4.21' apply false" "$root_build"
grep -Fq "include ':app', ':fx-gkd-selector'" "$settings"
grep -Fq "implementation project(':fx-gkd-selector')" "$app_build"
grep -Fq "commonMain/kotlin" "$module"
grep -Fq "jvmMain/kotlin" "$module"
grep -Fq "commonTest/kotlin" "$module"
grep -Fq "jvmTest/kotlin" "$module"
grep -Fq "vendor/GKD-XA/gkd-selector/src" "$module"

grep -Fq "Selector.compile(normalized)" "$engine"
grep -Fq "selector.validateType(typeModel)" "$engine"
grep -Fq "querySelectorAll(root, selector" "$engine"
grep -Fq "MAX_NODES = 700" "$snapshot"
grep -Fq "MAX_DEPTH = 32" "$snapshot"
grep -Fq "MAX_TEXT_LENGTH = 256" "$snapshot"
grep -Fq "info.isPassword || info.isEditable" "$snapshot"
grep -Fq "FxGkdRuleStore.isEnabled(service)" "$automation"
grep -Fq "rule.source.packageName == eventPackage" "$automation"
grep -Fq "liveNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)" "$automation"
grep -Fq "cooldownMillis" "$automation"
grep -Fq "getBoolean(KEY_MASTER_ENABLED, false)" "$rules"
grep -Fq "matchesUpstreamAttributeAndWidgetSelectors" "$unit"

manifest="$root/adhook/app/src/main/AndroidManifest.xml"
! grep -Eq 'li\.gkd\.app|gkd\.service\.|gkd\.app\.service|GkdTileService|A11yService' "$manifest" || {
  echo "FAIL: GKD-XA second app/service identity must not be copied into FX Manifest"
  exit 1
}

manifest="$root/adhook/app/src/main/AndroidManifest.xml"
! grep -Eq 'li\.gkd\.app|gkd\.service\.|gkd\.app\.service|GkdTileService|A11yService' "$manifest" || {
  echo "FAIL: GKD-XA second app/service identity must not be copied into FX Manifest"
  exit 1
}

echo "PASS: GKD selector uses the pinned source module; snapshot and local rule/action helpers are bounded; FX remains the only app/service identity."
