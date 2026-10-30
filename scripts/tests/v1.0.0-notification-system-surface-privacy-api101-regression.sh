#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
NP="adhook/app/src/main/java/de/privacyguard/adhook/NotificationPrivacyPolicy.java"
SP="adhook/app/src/main/java/de/privacyguard/adhook/SystemSurfacePrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installNotificationPrivacyHooks' "$SRC" || fail 'notification hook installer missing'
grep -q 'getActiveNotifications' "$SRC" || fail 'active notification enumeration missing'
grep -q 'areNotificationsEnabled' "$SRC" || fail 'notification permission query missing'
grep -q 'emptyCollectionResult' "$SRC" || fail 'type-compatible empty result helper missing'
grep -q 'installUsageStatsPrivacyHooks' "$SRC" || fail 'usage stats hook installer missing'
grep -q 'queryUsageStats' "$SRC" || fail 'usage stats query interception missing'
grep -q 'installAccessibilityPrivacyHooks' "$SRC" || fail 'accessibility hook installer missing'
grep -q 'getEnabledAccessibilityServiceList' "$SRC" || fail 'enabled accessibility service enumeration missing'
grep -q 'getInstalledAccessibilityServiceList' "$SRC" || fail 'installed accessibility service enumeration missing'
grep -q 'case "block_notif_listen"' "$PARSER" || fail 'notification history config flag missing'
grep -q 'case "hide_notif_perm"' "$PARSER" || fail 'notification permission config flag missing'
grep -q 'case "usagestats_off"' "$PARSER" || fail 'usage stats config flag missing'
grep -q 'case "a11y_hide"' "$PARSER" || fail 'accessibility config flag missing'
grep -q 'block_notif_listen' "$SER" || fail 'notification history serializer flag missing'
grep -q 'hide_notif_perm' "$SER" || fail 'notification permission serializer flag missing'
grep -q 'usagestats_off' "$SER" || fail 'usage stats serializer flag missing'
grep -q 'a11y_hide' "$SER" || fail 'accessibility serializer flag missing'
grep -q 'processPackageCount != 1' "$NP" || fail 'notification shared-process fail-open missing'
grep -q 'processPackageCount != 1' "$SP" || fail 'system surface shared-process fail-open missing'
echo 'FX API101 notification/usage/accessibility privacy regression: PASS'
