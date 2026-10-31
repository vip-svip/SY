#!/bin/sh
# Guard against falsely claiming single-APK parity before all legacy switches migrate.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE="$ROOT/fx-module"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q "未完成，当前保留双 APK" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "incomplete migration status missing"
grep -q "75 个旧版配置开关" "$ROOT/docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md" || fail "legacy switch count not documented"
grep -q "de.privacyguard.hook" "$MODULE/scripts/install_adhook_app.sh" || fail "legacy package install path missing"
grep -q "de.privacyguard.adhook" "$MODULE/scripts/install_adhook_app.sh" || fail "modern package install path missing"
grep -q "optional/PrivacyGuardHook.apk" "$MODULE/scripts/install_adhook_app.sh" || fail "legacy APK install path missing"
grep -q "optional/FXAdHook.apk" "$MODULE/scripts/install_adhook_app.sh" || fail "modern APK install path missing"
grep -q "de.privacyguard.hook.MainHook" "$MODULE/lsposed/app/src/main/assets/xposed_init" || fail "legacy runtime source entrypoint missing"
grep -q "de.privacyguard.adhook.AdVisibilityHook" "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "modern runtime entrypoint missing"
[ "$(grep -c '^| ' "$MODULE/docs/FXHOOK-MIGRATION-MATRIX.md")" -eq 76 ] || fail "75-switch migration matrix changed unexpectedly"
echo "PASS: legacy and modern Hook packages remain installed until 75-switch migration is complete"

ADHOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
grep -q 'final boolean developerTestForPackage = false;' "$ADHOOK" || fail "production developer override hooks must remain disabled"
if grep -q 'installDeveloperBooleanTestHook(param.getClassLoader(), pkg, true, target.developerVipMethod\|installDeveloperBooleanTestHook(param.getClassLoader(), pkg, true, target.developerLoginMethod\|installDeveloperBooleanTestHook(param.getClassLoader(), pkg, true, target.developerHideUpdateMethod' "$ADHOOK"; then
  fail "production Hook must not override VIP/login/update decisions"
fi
