#!/system/bin/sh
# Integration regression for modern LSPosed Remote Files config publication.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
GEN="$ROOT/scripts/gen_xposed_conf.sh"
APPLY="$ROOT/scripts/apply.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$GEN" ] || fail "config generator missing"
[ -s "$APPLY" ] || fail "apply.sh missing"
grep -q 'xposed-remote.status' "$APPLY" || fail "apply must discard stale remote status"
grep -q 'LSPosed Remote Files 配置发布未确认' "$APPLY" || fail "apply must not report false success when remote publish fails"
grep -q '_HOOK_PRIVACY_ENABLED=$(pg_get hook_privacy_enabled 0' "$APPLY" || fail "privacy-only Hook master must be included in publication gate"
grep -q '_HOOK_NOTIFICATION_LISTEN_ENABLED=$(pg_get block_notif_listen 0' "$APPLY" || fail "notification-listen master must be included in publication gate"
grep -q '_HOOK_NOTIFICATION_PERMISSION_HIDE_ENABLED=$(pg_get hide_notif_perm 0' "$APPLY" || fail "notification-permission query master must be included in publication gate"
grep -Fq '[ "$_HOOK_ADS_ENABLED" = "1" ] || [ "$_HOOK_PRIVACY_ENABLED" = "1" ] || [ "$_HOOK_WIFI_SCAN_ENABLED" = "1" ] || [ "$_HOOK_NOTIFICATION_LISTEN_ENABLED" = "1" ] || [ "$_HOOK_NOTIFICATION_PERMISSION_HIDE_ENABLED" = "1" ] || [ "$_HOOK_CLIPBOARD_ISOLATE_ENABLED" = "1" ]' "$APPLY" || fail "every independent Hook master must require successful Remote Files publication"
grep -q '_HOOK_MEMBER_DIAG_TARGETS=' "$APPLY" || fail "member diagnostics target count missing from apply gate"
grep -Fq '[ "$_HOOK_MEMBER_DIAG_TARGETS" -gt 0 ]' "$APPLY" || fail "member-only target must trigger Remote Files publication"
TMP="${TMPDIR:-/tmp}/fx-lsposed-remote-test-$$"
mkdir -p "$TMP/pg" "$TMP/bin" "$TMP/lspd" || fail "cannot create fixtures"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cat > "$TMP/settings.conf" <<'CONF'
lsposed_enabled=0
lsposed_profile=compat
hook_ads_enabled=1
hook_privacy_enabled=0
block_wifi_scan=1
block_notif_listen=1
hide_notif_perm=1
clipboard_isolate=1
[list:hook_targets]
com.example.app,splash=1,feed=1,overlay=0,member_diag=1,privacy=0|FX LSPosed Hook|1
com.privacy.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=1|Privacy Hook|1
com.exif.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,exif_strip=1|EXIF privacy|1
com.clip.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=1|Clipboard privacy|1
com.wifi.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,wifi_scan_block=1|Wi-Fi privacy|1
com.notify.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,notification_listen_block=1|Notification privacy|1
com.notifyperm.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,notification_permission_hide_block=1|Notification permission query privacy|1
com.clipiso.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,clipboard_isolate=1|Clipboard isolation|1
com.sensitive.app,splash=0,feed=0,overlay=0,member_diag=0,privacy=0,camera_access_block=1,location_access_block=1,mic_access_block=1,media_store_query_block=1|Explicit privacy denials|1
bad package,splash=1,feed=0,overlay=0,member_diag=0|invalid package|1
com.disabled.app,splash=1,feed=1,overlay=1,member_diag=0|disabled target|0
CONF
cat > "$TMP/bin/pm" <<'SH'
#!/bin/sh
printf 'Users:\n    UserInfo{0:Owner:c13} running\n    UserInfo{10:Work profile:c13} running\n'
SH
cat > "$TMP/bin/chcon" <<'SH'
#!/bin/sh
[ "${CHCON_FAIL:-0}" != 1 ]
SH
cat > "$TMP/bin/chown" <<'SH'
#!/bin/sh
exit 0
SH
chmod 0755 "$TMP/bin/pm" "$TMP/bin/chcon" "$TMP/bin/chown"
PATH="$TMP/bin:$PATH" PG="$TMP/pg" CONF="$TMP/settings.conf" \
  PG_XPOSED_DIR="$TMP/xposed" PG_LSPOSED_REMOTE_ROOT="$TMP/lspd" \
  sh "$GEN" >/dev/null 2>&1 || fail "generator failed"
for uid in 0 10; do
  OUT="$TMP/lspd/modules/$uid/de.privacyguard.adhook/files/fx-hook-targets.conf"
  [ -s "$OUT" ] || fail "Remote Files config missing for user $uid"
  grep -q '^schema_version=1$' "$OUT" || fail "modern schema version not published for user $uid"
  grep -q '^ads_enabled=1$' "$OUT" || fail "ads master switch not published for user $uid"
  grep -q '^privacy_enabled=0$' "$OUT" || fail "privacy must remain disabled by default for user $uid"
  grep -q '^wifi_scan_enabled=1$' "$OUT" || fail "legacy Wi-Fi scan master was not published independently for user $uid"
  grep -q '^notification_listen_enabled=1$' "$OUT" || fail "legacy notification-listen master was not published independently for user $uid"
  grep -q '^notification_permission_hide_enabled=1$' "$OUT" || fail "notification permission-query master was not published independently for user $uid"
  grep -q '^clipboard_isolate_enabled=1$' "$OUT" || fail "clipboard isolation master not published for user $uid"
  grep -q '^\[list:targets\]$' "$OUT" || fail "modern target section missing for user $uid"
  grep -q '^com.example.app,ads_splash=1,ads_feed=1,ads_overlay=0,member_diag=1,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "valid target missing or not translated for user $uid"
  grep -q '^com.privacy.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=1,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "per-app privacy target missing for user $uid"
  grep -q '^com.exif.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=1,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "EXIF-only target missing or lost in Remote Files publication for user $uid"
  grep -q '^com.clip.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=1,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "clipboard-only target missing or lost in Remote Files publication for user $uid"
  grep -q '^com.wifi.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=1,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "Wi-Fi scan target missing or not translated for user $uid"
  grep -q '^com.notify.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=1,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "notification-listen target missing or not translated for user $uid"
  grep -q '^com.notifyperm.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=1,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "notification permission-query target missing or not translated for user $uid"
  grep -q '^com.clipiso.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=1,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "clipboard isolation target missing or not translated for user $uid"
  grep -q '^com.sensitive.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=1,location_access_block=1,mic_access_block=1,media_store_query_block=1$' "$OUT" || fail "camera/location/microphone/MediaStore controls missing from Remote Files"
  if grep -q 'bad package\|com.disabled.app' "$OUT"; then fail "invalid/disabled target leaked for user $uid"; fi
  if grep -q '\[conf:' "$OUT"; then fail "unrelated config leaked into app-side file"; fi
done
# Verify unsupported legacy developer-hook fields do not leak into API-101 schema.
OUT="$TMP/lspd/modules/0/de.privacyguard.adhook/files/fx-hook-targets.conf"
if grep -Eq '(^|,)dev_hook_enabled=|(^|,)dev_rule_[0-9]+=' "$OUT"; then
  fail "unsupported developer-hook fields leaked into the runtime schema"
fi
grep -q '^schema_version=1$' "$OUT" || fail "Remote Files schema version missing"
grep -q '^ads_enabled=1$' "$OUT" || fail "automatic Ad master missing"
grep -q '^\[list:targets\]$' "$OUT" || fail "Remote Files target section missing"
# Member diagnostics alone must publish even with the ad-filtering master off.
cat > "$TMP/settings-member-only.conf" <<'CONF'
hook_ads_enabled=0
hook_privacy_enabled=0
block_wifi_scan=0
block_notif_listen=0
hide_notif_perm=0
clipboard_isolate=0
[list:hook_targets]
com.member.only,splash=0,feed=0,overlay=0,member_diag=1|Member diagnostics only|1
CONF
mkdir -p "$TMP/lspd-member-only" || fail "cannot create member-only LSPosed root"
PATH="$TMP/bin:$PATH" PG="$TMP/pg" CONF="$TMP/settings-member-only.conf" \
  PG_XPOSED_DIR="$TMP/xposed-member-only" PG_LSPOSED_REMOTE_ROOT="$TMP/lspd-member-only" \
  sh "$GEN" >/dev/null 2>&1 || fail "generator failed for member-only config"
OUT="$TMP/lspd-member-only/modules/0/de.privacyguard.adhook/files/fx-hook-targets.conf"
[ -s "$OUT" ] || fail "member-only Remote Files config missing"
grep -q '^ads_enabled=0$' "$OUT" || fail "member-only config must preserve disabled ad master"
grep -q '^com.member.only,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=1,privacy=0,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "member-only target was not translated"
grep -q '^status=ok$' "$TMP/xposed-member-only/xposed-remote.status" || fail "member-only Remote Files publish not recorded as successful"
grep -q '^status=ok$' "$TMP/xposed/xposed-remote.status" || fail "remote publication not recorded as successful"
# Independent privacy master must be published without changing the ad master,
# and the per-app privacy bit must survive the settings -> Remote Files path.
sed 's/^hook_privacy_enabled=0$/hook_privacy_enabled=1/' "$TMP/settings.conf" > "$TMP/settings-privacy-on.conf"
mkdir -p "$TMP/lspd-privacy-on" || fail "cannot create privacy-enabled LSPosed root"
PATH="$TMP/bin:$PATH" PG="$TMP/pg" CONF="$TMP/settings-privacy-on.conf" \
  PG_XPOSED_DIR="$TMP/xposed-privacy-on" PG_LSPOSED_REMOTE_ROOT="$TMP/lspd-privacy-on" \
  sh "$GEN" >/dev/null 2>&1 || fail "generator failed with privacy master enabled"
OUT="$TMP/lspd-privacy-on/modules/0/de.privacyguard.adhook/files/fx-hook-targets.conf"
[ -s "$OUT" ] || fail "privacy-enabled Remote Files config missing"
grep -q '^ads_enabled=1$' "$OUT" || fail "privacy master changed ad master unexpectedly"
grep -q '^privacy_enabled=1$' "$OUT" || fail "privacy master was not published independently"
grep -q '^wifi_scan_enabled=1$' "$OUT" || fail "Wi-Fi scan master was not preserved when privacy master enabled"
grep -q '^notification_listen_enabled=1$' "$OUT" || fail "notification-listen master was not preserved when privacy master enabled"
grep -q '^com.privacy.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=1,exif_strip=0,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "per-app privacy target lost when privacy master enabled"
grep -q '^com.exif.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=1,clipboard_read_block=0,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "EXIF-only target lost when privacy master enabled"
grep -q '^com.clip.app,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,privacy=0,exif_strip=0,clipboard_read_block=1,clipboard_isolate=0,sensor_accel=0,sensor_gyro=0,sensor_light=0,sensor_magnet=0,sensor_pressure=0,sensor_prox=0,sensor_rate_limit=0,wifi_scan_block=0,notification_listen_block=0,notification_permission_hide=0,mic_silence=0,camera_access_block=0,location_access_block=0,mic_access_block=0,media_store_query_block=0$' "$OUT" || fail "clipboard-only target lost when privacy master enabled"
# Fail closed if required SELinux labeling cannot be set.
mkdir -p "$TMP/lspd-fail"
PATH="$TMP/bin:$PATH" CHCON_FAIL=1 PG="$TMP/pg" CONF="$TMP/settings.conf" \
  PG_XPOSED_DIR="$TMP/xposed-fail" PG_LSPOSED_REMOTE_ROOT="$TMP/lspd-fail" \
  sh "$GEN" >/dev/null 2>&1 || fail "generator failed before recording failed remote publish"
grep -q '^status=failed$' "$TMP/xposed-fail/xposed-remote.status" || fail "SELinux label failure was not reported"
echo "PASS: LSPosed Remote Files config is per-user, minimal, atomic, fail-closed, and includes clipboard isolation plus notification permission-query master/per-app gates"
