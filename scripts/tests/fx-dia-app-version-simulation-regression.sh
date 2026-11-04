#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SERIALIZER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MAIN" "$PARSER" "$SERIALIZER" "$HOOK"; do [ -s "$file" ] || fail "missing app-version migration source: $file"; done
grep -Fq 'showAppList("应用版本模拟")' "$MAIN" || fail "Dia application-version page must open per-app editor"
grep -Fq 'FxDiaSignatureActivity.class' "$MAIN" || fail "signature information must remain a separate page"
grep -Fq 'app_version_simulate' "$MAIN" || fail "per-target version opt-in is not published"
grep -Fq 'app_version_name_b64' "$MAIN" || fail "versionName must be encoded before CSV config publishing"
grep -Fq 'app_version_code' "$MAIN" || fail "versionCode is not published"
grep -Fq 'decodeDeveloperRuleValue(value)' "$PARSER" || fail "encoded versionName does not use URL-safe UTF-8 decoding"
grep -Fq 'app version simulation requires version name and code' "$PARSER" || fail "parser must require both version fields"
grep -Fq 'app_version_name_b64' "$SERIALIZER" || fail "serializer does not preserve app version values"
grep -Fq 'Class.forName("android.app.ApplicationPackageManager"' "$HOOK" || fail "runtime does not hook PackageManager implementation"
grep -Fq '"getPackageInfo".equals(name)' "$HOOK" || fail "PackageInfo query interception is missing"
grep -Fq 'activePackage.equals(requestedPackage)' "$HOOK" || fail "runtime is not scoped to self-package queries"
grep -Fq 'debuggablePackages.contains(activePackage)' "$HOOK" || fail "runtime must reject non-debuggable target simulation"
grep -Fq 'info.versionName = active.simulatedVersionName;' "$HOOK" || fail "runtime does not replace versionName"
grep -Fq 'info.versionCode = (int) active.simulatedVersionCode;' "$HOOK" || fail "runtime does not replace versionCode"
echo "PASS: Dia app version simulation is per-target, encoded, debuggable-only and separate from signature inspection"
