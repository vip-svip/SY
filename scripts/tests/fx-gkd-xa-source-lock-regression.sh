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
adapter="$root/adhook/fx-gkd-selector/build.gradle"
readme="$root/adhook/fx-gkd-selector/README.md"
settings="$root/adhook/settings.gradle"
root_build="$root/adhook/build.gradle"
app_build="$root/adhook/app/build.gradle"
runtime="$root/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdSelectorRuntime.kt"
runtime_test="$root/adhook/app/src/test/java/de/privacyguard/adhook/FxGkdSelectorRuntimeTest.kt"
workflow="$root/.github/workflows/fx-gkd-selector.yml"
for file in "$plan" "$adapter" "$readme" "$settings" "$root_build" "$app_build" "$runtime" "$runtime_test" "$workflow"; do
  expect_file "$file"
done

grep -Fq '### 已实际接入的第一阶段' "$plan" || fail "GKD integration plan does not record selector stage as implemented"
grep -Fq '### 仍未完成，不能宣称 GKD 已完整迁入' "$plan" || fail "GKD integration plan must retain the remaining-work boundary"
grep -Fq 'GPL-3.0' "$readme" || fail "GKD selector GPL provenance missing"
grep -Fq "commonMain/kotlin" "$adapter" || fail "upstream commonMain source set not wired"
grep -Fq "jvmMain/kotlin" "$adapter" || fail "upstream jvmMain source set not wired"
grep -Fq "commonTest/kotlin" "$adapter" || fail "upstream commonTest suite not wired"
grep -Fq "jvmTest/kotlin" "$adapter" || fail "upstream jvmTest suite not wired"
grep -Fq "kotlinx-serialization-json:1.11.0" "$adapter" || fail "upstream test serialization dependency missing"
grep -Fq "li.songe:json5:0.8.0" "$adapter" || fail "upstream JSON5 fixture dependency missing"
grep -Fq "kotlinOptions.jvmTarget = '17'" "$adapter" || fail "selector adapter JVM target is not 17"
grep -Fq "org.jetbrains.kotlin.plugin.serialization" "$root_build" || fail "Kotlin serialization plugin is not registered"
grep -Fq "include ':app', ':fx-gkd-selector'" "$settings" || fail "single selector project is not included"
grep -Fq "implementation project(':fx-gkd-selector')" "$app_build" || fail "FX APK is not linked to the selector library"
if grep -Fq 'gkd-selector-adapter' "$settings" "$app_build"; then
  fail "duplicate selector adapter project remains wired"
fi
if grep -Fq "project(':gkd-app')" "$app_build"; then
  fail "upstream second Android application must not be packaged"
fi

grep -Fq 'fun compile(source: String)' "$runtime" || fail "FX selector compile API missing"
grep -Fq 'fun findFirst(' "$runtime" || fail "Accessibility first-match API missing"
grep -Fq 'fun findAll(' "$runtime" || fail "bounded Accessibility enumeration API missing"
grep -Fq 'MAX_SELECTOR_CHARS = 8_192' "$runtime" || fail "selector source length guard missing"
grep -Fq 'FxGkdSelectorRuntime.compile(' "$runtime_test" || fail "FX runtime tests are not exercising the selector"
grep -Fq ':fx-gkd-selector:jvmTest' "$workflow" || fail "focused JVM test workflow does not run upstream selector suites"

echo "PASS: GKD-XA v1.4.8 GPL source pin, single Java 17 selector module, full upstream test source sets, FX Accessibility adapter and remaining-work boundary verified."
