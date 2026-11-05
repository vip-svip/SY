#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
gitmodules="$root/.gitmodules"
test -s "$gitmodules" || { echo "FAIL: GKD-XA submodule declaration missing"; exit 1; }
git config -f "$gitmodules" --get submodule.vendor/GKD-XA.path | grep -Fxq 'vendor/GKD-XA'
git config -f "$gitmodules" --get submodule.vendor/GKD-XA.url | grep -Fxq 'https://github.com/84593320z/GKD-XA.git'
gitlink="$(git -C "$root" ls-tree HEAD vendor/GKD-XA)"
[[ "$gitlink" == "160000 commit 8a6ce935da11671dac7e1a7595416ec99ee07436"$'\t'"vendor/GKD-XA" ]] || {
  echo "FAIL: GKD-XA is not pinned to the reviewed v1.4.8 commit"
  echo "$gitlink"
  exit 1
}
grep -Fq '尚未合并进 FX APK' "$root/docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md"

# The complete upstream selector source is consumed from the pinned GPL submodule
# by a standalone JVM library; do not link the upstream gkd-app application module.
adapter="$root/adhook/gkd-selector-adapter/build.gradle"
app_build="$root/adhook/app/build.gradle"
settings="$root/adhook/settings.gradle"
test_source="$root/adhook/gkd-selector-adapter/src/jvmTest/kotlin/de/privacyguard/adhook/gkd/GkdSelectorSmokeTest.kt"
test -s "$adapter" && test -s "$app_build" && test -s "$settings" && test -s "$test_source"
grep -Fq "vendor/GKD-XA/gkd-selector/src/commonMain/kotlin" "$adapter"
grep -Fq "vendor/GKD-XA/gkd-selector/src/jvmMain/kotlin" "$adapter"
grep -Fq "jvmToolchain(17)" "$adapter"
grep -Fq "include ':app', ':gkd-selector-adapter'" "$settings"
grep -Fq "implementation project(':gkd-selector-adapter')" "$app_build"
! grep -Fq "project(':gkd-app')" "$app_build"
grep -Fq "Selector.compile(" "$test_source"
grep -Fq 'The upstream selector sources are not modified in place' "$root/adhook/gkd-selector-adapter/README.md"
echo "PASS: GKD-XA v1.4.8 selector source pin, GPL provenance, Java 17 adapter wiring and parser smoke tests are present; upstream app/services remain excluded."
