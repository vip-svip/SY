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
# by the single :fx-gkd-selector JVM library; do not link the upstream gkd-app application module.
adapter="$root/adhook/fx-gkd-selector/build.gradle"
app_build="$root/adhook/app/build.gradle"
settings="$root/adhook/settings.gradle"
readme="$root/adhook/fx-gkd-selector/README.md"
test -s "$adapter" && test -s "$app_build" && test -s "$settings" && test -s "$readme"
grep -Fq "commonMain/kotlin" "$adapter"
grep -Fq "jvmMain/kotlin" "$adapter"
grep -Fq "commonTest/kotlin" "$adapter"
grep -Fq "jvmTest/kotlin" "$adapter"
grep -Fq "kotlinx-serialization-json:1.11.0" "$adapter"
grep -Fq "li.songe:json5:0.8.0" "$adapter"
grep -Fq "kotlinOptions.jvmTarget = '17'" "$adapter"
grep -Fq "include ':app', ':fx-gkd-selector'" "$settings"
grep -Fq "implementation project(':fx-gkd-selector')" "$app_build"
! grep -Fq "gkd-selector-adapter" "$settings"
! grep -Fq "gkd-app" "$app_build"
grep -Fq 'upstream GPL notices' "$readme"
echo "PASS: GKD-XA v1.4.8 selector source pin, GPL provenance, Java 17 adapter wiring and parser smoke tests are present; upstream app/services remain excluded."
