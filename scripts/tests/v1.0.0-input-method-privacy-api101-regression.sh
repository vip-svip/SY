#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/InputMethodPrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installInputMethodPrivacyHooks' "$SRC" || fail 'input-method hook installer missing'
grep -q 'getEnabledInputMethodList' "$SRC" || fail 'enabled IME list interception missing'
grep -q 'getInputMethodList' "$SRC" || fail 'IME list interception missing'
grep -q 'getEnabledInputMethodSubtypeList' "$SRC" || fail 'IME subtype list interception missing'
grep -q 'InputMethodPrivacyPolicy.shouldHideInputMethods' "$SRC" || fail 'fail-open policy not connected'
grep -q 'case "block_ime_logging"' "$PARSER" || fail 'block_ime_logging parser flag missing'
grep -q 'block_ime_logging' "$SER" || fail 'block_ime_logging serializer flag missing'
grep -q 'processPackageCount == 1' "$POLICY" || fail 'single-package fail-open missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected package exclusion missing'
echo 'FX API101 input-method privacy regression: PASS'
