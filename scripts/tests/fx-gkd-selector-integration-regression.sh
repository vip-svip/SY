#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
module="$root/adhook/fx-gkd-selector/build.gradle"
runtime="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorRuntime.kt"
unit="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorRuntimeTest.kt"
app_build="$root/adhook/app/build.gradle"
settings="$root/adhook/settings.gradle"
root_build="$root/adhook/build.gradle"
plan="$root/docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md"

for file in "$module" "$runtime" "$unit" "$app_build" "$settings" "$root_build" "$plan"; do
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

grep -Fq "Selector.parse(source)" "$runtime"
grep -Fq "selector.validateType(typeModel)" "$runtime"
grep -Fq "MAX_SELECTOR_CHARS" "$runtime"
grep -Fq "MAX_DESCENDANTS_PER_QUERY" "$runtime"
grep -Fq "MAX_FAST_QUERY_RESULTS" "$runtime"
grep -Fq "isMatchRoot" "$runtime"
grep -Fq "query.accepts(attribute?.toString() ?: "")" "$runtime"
grep -Fq "does not start a second" "$runtime"
grep -Fq "never clicks or changes UI state" "$runtime"

grep -Fq "rejectsSyntaxErrorsWithSourceOffsets" "$unit"
grep -Fq "rejectsUnknownAccessibilityPropertiesDuringTypeCheck" "$unit"
grep -Fq "enforcesBoundedSelectorSourceLength" "$unit"
grep -Fq "尚未合并进 FX APK" "$plan"

manifest="$root/adhook/app/src/main/AndroidManifest.xml"
! grep -Eq 'li\.gkd\.app|gkd\.service\.|gkd\.app\.service|GkdTileService|A11yService' "$manifest" || {
  echo "FAIL: GKD-XA second app/service identity must not be copied into FX Manifest"
  exit 1
}

echo "PASS: GKD selector uses the pinned source module, is wired into the FX APK, has a bounded read-only Accessibility adapter, and does not add a second service/application identity."
