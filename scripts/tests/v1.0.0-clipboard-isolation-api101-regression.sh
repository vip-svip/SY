#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/ClipboardIsolationPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installClipboardIsolationHooks' "$SRC" || fail 'clipboard isolation installer missing'
grep -q 'getPrimaryClipDescription' "$SRC" || fail 'clipboard description interception missing'
grep -q 'setPrimaryClip' "$SRC" || fail 'clipboard write isolation missing'
grep -q 'isolatedClipboard.put(activePackage' "$SRC" || fail 'process-local clipboard storage missing'
grep -q 'shouldIsolateClipboard' "$SRC" || fail 'clipboard isolation policy not connected'
grep -q 'case "clipboard_isolate"' "$PARSER" || fail 'clipboard isolation parser flag missing'
grep -q 'clipboard_isolate' "$SER" || fail 'clipboard isolation serializer flag missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
grep -q 'target.clipboardReadBlock' "$POLICY" || fail 'read-block precedence missing'
grep -q 'org.lsposed.manager' "$POLICY" || fail 'protected package exclusion missing'
echo 'FX API101 clipboard isolation regression: PASS'
