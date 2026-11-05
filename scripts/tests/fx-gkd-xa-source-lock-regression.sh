#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_file() { [[ -s "$1" ]] || fail "required integration file missing: ${1#"$root"/}"; }

gitmodules="$root/.gitmodules"
expect_file "$gitmodules"
submodule_path="$(git config -f "$gitmodules" --get submodule.vendor/GKD-XA.path || true)"
submodule_url="$(git config -f "$gitmodules" --get submodule.vendor/GKD-XA.url || true)"
[[ "$submodule_path" == "vendor/GKD-XA" ]] || fail "GKD-XA submodule path mismatch: $submodule_path"
[[ "$submodule_url" == "https://github.com/84593320z/GKD-XA.git" ]] || fail "GKD-XA submodule URL mismatch: $submodule_url"

expected_gitlink="160000 commit 8a6ce935da11671dac7e1a7595416ec99ee07436"$'\t'"vendor/GKD-XA"
actual_gitlink="$(git -C "$root" ls-tree HEAD vendor/GKD-XA)"
[[ "$actual_gitlink" == "$expected_gitlink" ]] || fail "GKD-XA gitlink is not pinned to v1.4.8: $actual_gitlink"

plan="$root/docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md"
module="$root/adhook/fx-gkd-selector/build.gradle"
readme="$root/adhook/fx-gkd-selector/README.md"
settings="$root/adhook/settings.gradle"
root_build="$root/adhook/build.gradle"
app_build="$root/adhook/app/build.gradle"
engine="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorEngine.kt"
engine_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorEngineTest.kt"
store="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt"
snapshot="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAccessibilitySnapshot.kt"
automation="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationRuntime.kt"
activity="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationActivity.java"
service="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java"
workflow="$root/.github/workflows/fx-gkd-selector.yml"
manifest="$root/adhook/app/src/main/AndroidManifest.xml"

for file in "$plan" "$module" "$readme" "$settings" "$root_build" "$app_build" \
            "$engine" "$engine_test" "$store" "$snapshot" "$automation" "$activity" \
            "$service" "$workflow" "$manifest"; do
  expect_file "$file"
done

# Exactly one selector library is part of the Android build graph.
grep -Fq "include ':app', ':fx-gkd-selector'" "$settings" || fail "single FX selector module not included"
grep -Fq "implementation project(':fx-gkd-selector')" "$app_build" || fail "FX app is not linked to the selector module"
! grep -Fq 'gkd-selector-adapter' "$settings" "$app_build" || fail "obsolete duplicate selector adapter remains wired"
! grep -Fq "project(':gkd-selector')" "$settings" "$app_build" || fail "obsolete duplicate selector project remains wired"
! grep -Fq "project(':gkd-app')" "$settings" "$app_build" || fail "upstream second Android application must not be packaged"
[[ ! -e "$root/adhook/gkd-selector" ]] || fail "obsolete duplicate gkd-selector directory remains"
[[ ! -e "$root/adhook/gkd-selector-adapter" ]] || fail "obsolete duplicate gkd-selector-adapter directory remains"

grep -Fq "id 'org.jetbrains.kotlin.multiplatform' version '2.4.21' apply false" "$root_build" || fail "Kotlin MPP plugin version mismatch"
grep -Fq "org.jetbrains.kotlin.plugin.serialization" "$root_build" || fail "upstream serialization plugin missing"
grep -Fq "commonMain/kotlin" "$module" || fail "upstream commonMain source set is not wired"
grep -Fq "jvmMain/kotlin" "$module" || fail "upstream jvmMain source set is not wired"
grep -Fq "commonTest/kotlin" "$module" || fail "upstream commonTest source set is not wired"
grep -Fq "jvmTest/kotlin" "$module" || fail "upstream jvmTest source set is not wired"
grep -Fq "kotlinOptions.jvmTarget = '17'" "$module" || fail "selector module JVM target is not 17"

# The app-side integration uses one engine, one bounded node snapshot, one local store,
# and the existing FX AccessibilityService — not the obsolete parser-only facade.
grep -Fq 'Selector.compile(normalized)' "$engine" || fail "upstream Selector compiler call missing"
grep -Fq 'selector.validateType(typeModel)' "$engine" || fail "upstream selector type validation missing"
grep -Fq 'querySelectorAll(root, selector' "$engine" || fail "upstream selector query adapter missing"
grep -Fq 'MAX_NODES = 700' "$snapshot" || fail "snapshot node bound missing"
grep -Fq 'MAX_DEPTH = 32' "$snapshot" || fail "snapshot depth bound missing"
grep -Fq 'info.isPassword || info.isEditable' "$snapshot" || fail "snapshot sensitive-node suppression missing"
grep -Fq 'MAX_RULES = 128' "$store" || fail "local rule cap missing"
grep -Fq 'getBoolean(KEY_MASTER_ENABLED, false)' "$store" || fail "GKD master switch does not default off"
grep -Fq 'FxGkdSelectorEngine.compile(expression)' "$store" || fail "local rule add does not compile selector"
grep -Fq 'FxGkdAutomationRuntime.process(this, eventPackage, root)' "$service" || fail "single FX service does not dispatch local GKD rules"
grep -Fq 'FxGkdRuleStore.hasEnabledRule(this, pkg)' "$service" || fail "event package scope gate missing"
grep -Fq 'AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS' "$service" || fail "resource ID selectors are not requested dynamically"
grep -Fq 'isInstalledUserApplication(service, eventPackage)' "$automation" || fail "runtime target package verification missing"
grep -Fq 'FxGkdRuleStore.isRuleEnabled(service, rule.source.id, eventPackage)' "$automation" || fail "action-time rule revocation check missing"
grep -Fq 'performAction(AccessibilityNodeInfo.ACTION_CLICK)' "$automation" || fail "first action executor is missing"
grep -Fq 'matchesUpstreamAttributeAndWidgetSelectors' "$engine_test" || fail "selector engine unit coverage missing"
grep -Fq 'respectsSelectorResultLimit' "$engine_test" || fail "selector result limit unit coverage missing"

# Single app/service identity and GPL provenance must remain explicit.
[[ "$(grep -Fc 'android:name=".FxAccessibilityService"' "$manifest")" -eq 1 ]] || fail "FX must declare exactly one AccessibilityService"
[[ "$(grep -Fc 'android:name=".FxGkdAutomationActivity"' "$manifest")" -eq 1 ]] || fail "GKD rules Activity must be declared exactly once"
[[ "$(grep -Fc 'android.intent.category.LAUNCHER' "$manifest")" -eq 1 ]] || fail "FX must keep one launcher"
! grep -Eq 'li\.gkd\.app|gkd\.service\.|gkd\.app\.service|GkdTileService|A11yService' "$manifest" || fail "upstream second app/service identity leaked into FX Manifest"
grep -Fq 'GPL-3.0' "$readme" || fail "GPL-3.0 provenance missing"
grep -Fq '8a6ce935da11671dac7e1a7595416ec99ee07436' "$readme" || fail "pinned upstream commit missing"
grep -Fq ':fx-gkd-selector:jvmTest' "$workflow" || fail "upstream JVM selector test lane missing"

grep -Fq '### 已落地：选择器、单服务事件管线与本地规则首批垂直切片' "$plan" || fail "integration plan does not reflect the implemented local slice"
grep -Fq '### 当前垂直切片明确不包括' "$plan" || fail "integration plan has no remaining-work boundary"
echo "PASS: pinned GKD-XA source, one selector module/engine, local opt-in rules, bounded snapshot, and one FX AccessibilityService are verified."
