#!/bin/sh
# Guard against falsely claiming single-APK parity before all legacy switches migrate.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q "未完成，当前保留双 APK" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "incomplete migration status missing"
grep -q "75 个旧版配置开关" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "legacy switch count not documented"
grep -q "de.privacyguard.hook" "$ROOT/scripts/install_adhook_app.sh" || fail "legacy package install path missing"
grep -q "de.privacyguard.adhook" "$ROOT/scripts/install_adhook_app.sh" || fail "modern package install path missing"
grep -q "optional/PrivacyGuardHook.apk" "$ROOT/scripts/install_adhook_app.sh" || fail "legacy APK install path missing"
grep -q "optional/FXAdHook.apk" "$ROOT/scripts/install_adhook_app.sh" || fail "modern APK install path missing"
grep -q "de.privacyguard.hook.MainHook" "$ROOT/lsposed/app/src/main/assets/xposed_init" || fail "legacy runtime source entrypoint missing"
grep -q "de.privacyguard.adhook.AdVisibilityHook" "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "modern runtime entrypoint missing"
[ "$(grep -c '^| `' "$ROOT/docs/FXHOOK-MIGRATION-MATRIX.md")" -eq 75 ] || fail "75-switch migration matrix changed unexpectedly"
echo "PASS: legacy and modern Hook packages remain installed until 75-switch migration is complete"
