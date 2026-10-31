#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
I="$ROOT/scripts/install_adhook_app.sh"; P="$ROOT/fx-module/scripts/install_adhook_app.sh"; A="$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md"
fail(){ echo "FAIL: $*" >&2; exit 1; }
cmp -s "$I" "$P" || fail "module installer drift"
grep -Fq 'optional/FXUnifiedHook.apk' "$I" || fail "unified APK install path missing"
! grep -Eq 'optional/(PrivacyGuardHook|FXAdHook)\.apk|install_one de\.privacyguard\.hook' "$I" || fail "stale two-APK installer remains"
grep -Fq 'de.privacyguard.adhook.AdVisibilityHook' "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "modern entrypoint missing"
grep -Fq 'de.privacyguard.hook.MainHook' "$ROOT/fx-module/lsposed/app/src/main/assets/xposed_init" || fail "legacy entrypoint missing"
grep -Fq '75' "$A" || fail "legacy migration caveat missing"
echo "PASS: one installer APK and both runtime entrypoints are present"
