#!/system/bin/sh
# Verify real backend LSPosed Remote Files status is exposed to UI without claiming scope is active.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
STATUS="$ROOT/scripts/status.sh"
UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$STATUS" ] || fail "status script missing"
[ -s "$UI" ] || fail "web UI missing"
grep -q 'HOOK_REMOTE_STATUS=' "$STATUS" || fail "remote status not read"
grep -q '"hook_remote_status":"%s"' "$STATUS" || fail "remote status missing from JSON"
grep -q '"hook_native_config_found":"%s"' "$STATUS" || fail "native overlay presence missing from JSON"
grep -q '"hook_native_privacy_enabled":"%s"' "$STATUS" || fail "native privacy status missing from JSON"
grep -q '"hook_native_wifi_scan_enabled":"%s"' "$STATUS" || fail "native Wi-Fi status missing from JSON"
grep -q '"hook_native_notification_listen_enabled":"%s"' "$STATUS" || fail "native notification status missing from JSON"
grep -q '"hook_native_notification_permission_hide_enabled":"%s"' "$STATUS" || fail "native notification permission status missing from JSON"
grep -q '"hook_native_clipboard_isolate_enabled":"%s"' "$STATUS" || fail "native clipboard status missing from JSON"
grep -q '"hook_native_member_diag_enabled":"%s"' "$STATUS" || fail "native member diagnostics status missing from JSON"
grep -q '"hook_ads_targets":%s' "$STATUS" || fail "target count missing from JSON"
grep -q '"hook_member_diag_enabled":"%s"' "$STATUS" || fail "member diagnostics state missing from JSON"
grep -q '"hook_member_diag_targets":%s' "$STATUS" || fail "member diagnostics target count missing from JSON"
grep -q '"hook_notification_permission_hide_enabled":"%s"' "$STATUS" || fail "notification permission-query master missing from JSON"
grep -q '"hook_notification_permission_hide_targets":%s' "$STATUS" || fail "notification permission-query target count missing from JSON"
grep -q '"hook_clipboard_isolate_enabled":"%s"' "$STATUS" || fail "clipboard isolation master missing from JSON"
grep -q '"hook_clipboard_isolate_targets":%s' "$STATUS" || fail "clipboard isolation target count missing from JSON"
grep -q 'hook_native_notification_permission_hide_enabled' "$UI" || fail "UI doesn't show notification permission-query status"
grep -q 'hook_native_clipboard_isolate_enabled' "$UI" || fail "UI doesn't show clipboard isolation status"
grep -q 'hook_native_member_diag_enabled' "$UI" || fail "UI does not show independent member diagnostics status"
grep -q '会员诊断仅记录应用内可观察状态' "$UI" || fail "UI does not explain read-only member diagnostics"
grep -q 'private void refreshHookRemoteStatus(TextView target)' "$UI"
grep -q 'hook_native_config_found' "$UI" || fail "native status UI does not distinguish missing overlay config"
grep -q 'hook_native_wifi_scan_enabled' "$UI" || fail "native status UI omits Wi-Fi overlay status" || fail "UI lacks backend status refresh"
grep -q "scripts/status.sh json" "$UI" || fail "UI doesn't query backend status"
grep -q 'Root 发布失败' "$UI" || fail "UI doesn't show publication failures"
grep -q '目标应用加入作用域' "$UI" || fail "UI claims scope is verifiable by FX"
grep -q 'dynamic' "$ROOT/scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh" || fail "APK regression lacks dynamic-view contract"
TMP="${TMPDIR:-/tmp}/fx-hook-remote-status-$$"
mkdir -p "$TMP/pg" "$TMP/xposed"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cat > "$TMP/pg/settings.conf" <<'CONF'
hook_ads_enabled=1
hide_notif_perm=1
clipboard_isolate=1
[list:hook_targets]
com.example.app,splash=1,feed=1,overlay=0,member_diag=0,notification_permission_hide_block=1,clipboard_isolate=1|FX LSPosed Hook|1
CONF
cat > "$TMP/xposed/xposed-remote.status" <<'STATUS'
status=ok
enabled=1
targets=1
updated=1760000000
STATUS
OUT=$(PG="$TMP/pg" PG_XPOSED_DIR="$TMP/xposed" sh "$STATUS" json 2>/dev/null) || fail "status JSON execution failed"
printf '%s' "$OUT" | grep -q '"hook_ads_enabled":"1"' || fail "enabled state missing"
printf '%s' "$OUT" | grep -q '"hook_ads_targets":1' || fail "target count incorrect"
printf '%s' "$OUT" | grep -q '"hook_remote_status":"ok"' || fail "published status incorrect"
printf '%s' "$OUT" | grep -q '"hook_remote_targets":1' || fail "published target count incorrect"
printf '%s' "$OUT" | grep -q '"hook_notification_permission_hide_enabled":"1"' || fail "notification permission-query master state incorrect"
printf '%s' "$OUT" | grep -q '"hook_notification_permission_hide_targets":1' || fail "notification permission-query target count incorrect"
printf '%s' "$OUT" | grep -q '"hook_clipboard_isolate_enabled":"1"' || fail "clipboard isolation master state incorrect"
printf '%s' "$OUT" | grep -q '"hook_clipboard_isolate_targets":1' || fail "clipboard isolation target count incorrect"
printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const x=JSON.parse(s);if(x.hook_remote_status!=="ok"||x.hook_ads_targets!==1||x.hook_notification_permission_hide_enabled!=="1"||x.hook_notification_permission_hide_targets!==1||x.hook_clipboard_isolate_enabled!=="1"||x.hook_clipboard_isolate_targets!==1)process.exit(2)})' || fail "JSON is not parseable/consistent"
cat > "$TMP/pg/settings.conf" <<'CONF'
hook_ads_enabled=0
hide_notif_perm=0
clipboard_isolate=0
[list:hook_targets]
com.member.only,splash=0,feed=0,overlay=0,member_diag=1|Member diagnostics only|1
CONF
OUT=$(PG="$TMP/pg" PG_XPOSED_DIR="$TMP/xposed" sh "$STATUS" json 2>/dev/null) || fail "member-only status JSON execution failed"
printf '%s' "$OUT" | grep -q '"hook_ads_enabled":"0"' || fail "member-only config unexpectedly enabled ad filtering"
printf '%s' "$OUT" | grep -q '"hook_ads_targets":0' || fail "member-only config counted as ad target"
printf '%s' "$OUT" | grep -q '"hook_member_diag_enabled":"1"' || fail "member-only diagnostics not enabled"
printf '%s' "$OUT" | grep -q '"hook_member_diag_targets":1' || fail "member-only diagnostics target count incorrect"
printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const x=JSON.parse(s);if(x.hook_ads_enabled!=="0"||x.hook_ads_targets!==0||x.hook_member_diag_enabled!=="1"||x.hook_member_diag_targets!==1)process.exit(2)})' || fail "member-only status JSON inconsistent"
echo "PASS: member diagnostics remain independently visible when the ad master switch is off"
echo "PASS: remote publication status, notification permission-query and clipboard-isolation master/target status, and target scope caveat are surfaced truthfully"
cat > "$TMP/pg/fx-native-hook-targets-0.conf" <<'NATIVE'
schema_version=1
ads_enabled=1
privacy_enabled=1
wifi_scan_enabled=1
notification_listen_enabled=1
notification_permission_hide_enabled=1
clipboard_isolate_enabled=1
[list:targets]
com.native.app,privacy=1,wifi_scan_block=1,notification_listen_block=1,notification_permission_hide=1,clipboard_isolate=1,member_diag=1
NATIVE
OUT=$(PG="$TMP/pg" PG_XPOSED_DIR="$TMP/xposed" sh "$STATUS" json 2>/dev/null) || fail "native overlay status JSON execution failed"
printf '%s' "$OUT" | grep -q '"hook_native_config_found":"1"' || fail "native overlay not detected"
printf '%s' "$OUT" | grep -q '"hook_native_config_users":1' || fail "native overlay user count incorrect"
printf '%s' "$OUT" | grep -q '"hook_native_privacy_enabled":"1"' || fail "native privacy master not read"
printf '%s' "$OUT" | grep -q '"hook_native_wifi_scan_enabled":"1"' || fail "native Wi-Fi master not read"
printf '%s' "$OUT" | grep -q '"hook_native_notification_listen_enabled":"1"' || fail "native notification master not read"
printf '%s' "$OUT" | grep -q '"hook_native_notification_permission_hide_enabled":"1"' || fail "native notification permission master not read"
printf '%s' "$OUT" | grep -q '"hook_native_clipboard_isolate_enabled":"1"' || fail "native clipboard master not read"
printf '%s' "$OUT" | grep -q '"hook_native_member_diag_enabled":"1"' || fail "native member diagnostics not derived from targets"
printf '%s' "$OUT" | grep -q '"hook_native_targets":1' || fail "native target count incorrect"
printf '%s' "$OUT" | grep -q '"hook_native_notification_permission_hide_targets":1' || fail "native notification permission target count incorrect"
printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const x=JSON.parse(s);if(x.hook_native_config_found!=="1"||x.hook_native_targets!==1||x.hook_native_member_diag_enabled!=="1"||x.hook_native_privacy_targets!==1)process.exit(2)})' || fail "native overlay JSON is inconsistent"
echo "PASS: native Hook status is derived from the unified APK overlay, not legacy settings.conf"
