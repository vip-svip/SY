#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" ] || fail "single APK merge audit missing"
grep -q "唯一 API-101" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "single API-101 architecture not documented"
grep -q "de.privacyguard.adhook" "$ROOT/adhook/app/build.gradle" || fail "unified package identity missing"
grep -q "io.github.libxposed:api:101.0.1" "$ROOT/adhook/app/build.gradle" || fail "modern API dependency missing"
grep -q "de.privacyguard.adhook.AdVisibilityHook" "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "single runtime entrypoint missing"
grep -q "de.privacyguard.adhook" "$ROOT/scripts/install_adhook_app.sh" || fail "unified APK install missing"
! grep -q "install_one de.privacyguard.hook" "$ROOT/scripts/install_adhook_app.sh" || fail "retired API-82 package is still installed"
grep -q "remove_legacy_if_fx_owned" "$ROOT/scripts/install_adhook_app.sh" || fail "ownership-safe legacy migration missing"
grep -q "签名不兼容时不卸载" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "upgrade safety acceptance missing"
echo "PASS: one API-101 package, one entrypoint, ownership-safe API-82 migration"
