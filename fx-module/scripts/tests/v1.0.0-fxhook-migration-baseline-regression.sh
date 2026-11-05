#!/bin/sh
# Host-runnable migration baseline guard. This checks inventory integrity only;
# it deliberately does NOT claim API-101 feature parity or device injection.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
LEGACY="$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java"
MATRIX="$ROOT/docs/FXHOOK-MIGRATION-MATRIX.md"
MODERN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
test -s "$LEGACY"
test -s "$MATRIX"
test -s "$MODERN"
KEYS=$(grep -oE 'on\("[^"]+"\)' "$LEGACY" | sort -u | wc -l | tr -d ' ')
ROWS=$(grep -c '^| `' "$MATRIX")
[ "$KEYS" -eq 75 ]
[ "$ROWS" -eq 75 ]
grep -q 'Xposed API 82' "$MATRIX"
grep -q 'libxposed API 101' "$MATRIX"
grep -q 'openRemoteFile' "$MODERN"
# Sensor API-101 parity is implemented for all six legacy sensor types and rate limiting.
for key in sensor_accel sensor_gyro sensor_light sensor_magnet sensor_pressure sensor_prox sensor_rate_limit; do
  grep -Fq "| \`$key\` | \`sensorHide\` | API-101 已迁移" "$MATRIX"
done
# Wi-Fi scan suppression is independently gated by the legacy global switch and per-app target.
grep -q "| \`block_wifi_scan\` | \`wifiScanHide\` | API-101 已迁移" "$MATRIX"
grep -q "WifiScanPrivacyPolicy.shouldBlock" "$MODERN"
# Notification-listener migration only suppresses active-notification reads.
grep -q "| \`block_notif_listen\` | \`notifHide\` | API-101 已迁移" "$MATRIX"
grep -q "NotificationPrivacyPolicy.shouldBlock" "$MODERN"
grep -q "notification_listen_enabled" "$ROOT/scripts/gen_xposed_conf.sh"
grep -q "clipboard_isolate_enabled" "$ROOT/scripts/gen_xposed_conf.sh"
grep -q "installClipboardIsolationHooks" "$MODERN"
grep -q "clipboard_isolate" "$ROOT/scripts/tests/v1.0.0-lsposed-clipboard-isolation-migration-regression.sh"
grep -q "wifi_scan_enabled" "$ROOT/scripts/gen_xposed_conf.sh"
# Ensure the unified module is not falsely marked complete while two APK IDs remain.
grep -q "applicationId 'de.privacyguard.adhook'" "$ROOT/adhook/app/build.gradle"
grep -q "applicationId 'de.privacyguard.hook'" "$ROOT/lsposed/app/build.gradle"
echo "PASS FXhook migration baseline: $KEYS legacy switches inventoried; 7 sensor switches + Wi-Fi scan + notification-listener reads + notification permission-query masking + process-local clipboard isolation source/config path migrated; remaining API-101 parity pending"
