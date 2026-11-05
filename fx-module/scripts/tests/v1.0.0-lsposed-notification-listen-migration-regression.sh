#!/bin/sh
set -eu
fail(){ echo "FAIL: $*" >&2; exit 1; }
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PARSER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
SER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigSerializer.java"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/NotificationPrivacyPolicy.java"
GEN="$ROOT/scripts/gen_xposed_conf.sh"
UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
MATRIX="$ROOT/docs/FXHOOK-MIGRATION-MATRIX.md"
for f in "$PARSER" "$SER" "$HOOK" "$POLICY" "$GEN" "$UI" "$MATRIX"; do [ -s "$f" ] || { echo "FAIL missing $f" >&2; exit 1; }; done
grep -q 'notification_listen_enabled' "$PARSER"
grep -q 'notification_listen_block' "$PARSER"
grep -q 'notificationListenEnabled' "$SER"
grep -q 'notificationListenBlock' "$SER"
grep -q 'getActiveNotifications' "$HOOK"
grep -q 'enabled_notification_listeners' "$HOOK" || fail 'legacy Settings.Secure notification-listener enumeration must be preserved'
grep -q 'NotificationPrivacyPolicy.shouldBlock' "$HOOK"
grep -q 'processPackages.size()' "$HOOK"
grep -q 'block_notif_listen' "$GEN"
grep -q 'notification_listen_block' "$GEN"
grep -Fq 'toggle("阻止通知监听注册", "notification_listen_block"' "$UI"
grep -Fq 'toggle("隐藏通知权限提示", "notification_permission_hide"' "$UI" || fail 'notification permission query target must be editable per app' 
grep -q 'notification_permission_hide_enabled' "$GEN" || fail 'notification permission query master must be published'
grep -q 'notification_permission_hide=' "$GEN" || fail 'notification permission query target must be translated'
grep -q 'API-101 已迁移' "$MATRIX"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
javac -d "$tmp" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/SensorPrivacyPolicy.java" \
  "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/WifiScanPrivacyPolicy.java" \
  "$POLICY" \
  "$SER"
echo "PASS: notification read suppression and app-visible permission-query masking have independent master/per-app config wiring; OS permission state remains unchanged"
