#!/system/bin/sh
# Host-runnable integration contract for per-app LSPosed ad hook config.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF_DEFAULT="$ROOT/scripts/default.conf"
GEN="$ROOT/scripts/gen_xposed_conf.sh"
UI="$ROOT/../adhook/app/src/main/assets/webroot/index.html"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$CONF_DEFAULT" ] || fail "default.conf missing"
[ -s "$GEN" ] || fail "generator missing"
[ -s "$UI" ] || fail "UI missing"
grep -q '^hook_ads_enabled=0$' "$CONF_DEFAULT" || fail "actual app hook must default off"
grep -q '^\[list:hook_targets\]$' "$CONF_DEFAULT" || fail "hook target list section missing"
# UID network blocking and app-side Hook must remain separate lists.
grep -q '^\[list:hook\]$' "$CONF_DEFAULT" || fail "legacy UID block list missing"
# Ensure generator exports the list and rejects unsupported keys/invalid package names.
grep -q '\[list:hook_targets\]' "$GEN" || fail "xposed target list not published"
grep -q 'member_diag' "$GEN" || fail "membership diagnostics field missing"
grep -q 'exif_strip' "$GEN" || fail "EXIF privacy field missing from publisher"
grep -q 'fx-hook-targets.conf' "$GEN" || fail "Remote Files config publisher missing"
grep -q 'xposed-remote.status' "$GEN" || fail "remote-publish status missing"
grep -Fq 'Dual entrypoints: legacy Xposed API 93+ and modern libxposed API 101' "$ROOT/optional/FXUnifiedHook-BUILD-INFO.txt" || fail "unified Hook API provenance missing"
TMP="${TMPDIR:-/tmp}/fx-hook-target-test-$$"
mkdir -p "$TMP/pg" "$TMP/mod" || fail "cannot create temp dirs"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cat > "$TMP/settings.conf" <<'CONF'
lsposed_enabled=0
lsposed_profile=compat
hook_ads_enabled=1
[list:hook]
com.example.networkblock|Legacy UID block only|1
[list:hook_targets]
com.example.app,splash=1,feed=1,overlay=0,member_diag=1|FX LSPosed Hook|1
bad package,splash=1,feed=0,overlay=0,member_diag=0|invalid package|1
com.bad.app,splash=1,exec=1,overlay=0,member_diag=0|unknown feature key|1
com.disabled.app,splash=1,feed=1,overlay=1,member_diag=0|disabled target|0
CONF
PG="$TMP/pg" CONF="$TMP/settings.conf" PG_XPOSED_DIR="$TMP/xposed" sh "$GEN" >/dev/null 2>&1 || fail "generator failed on valid settings"
OUT="$TMP/xposed/xposed.conf"
[ -s "$OUT" ] || fail "xposed.conf missing"
grep -q '^hook_ads_enabled=1$' "$OUT" || fail "master switch not passed to Xposed config"
grep -q '^\[list:hook_targets\]$' "$OUT" || fail "target section absent in published config"
grep -q '^com.example.app,splash=1,feed=1,overlay=0,member_diag=1|FX LSPosed Hook|1$' "$OUT" || fail "valid target row not passed exactly"
if grep -q 'bad package\|com.bad.app\|com.disabled.app' "$OUT"; then fail "invalid/disabled target leaked into Xposed config"; fi
# The UI must offer actual application selection and distinguish UID blocking.
grep -q '应用网络阻断（UID）' "$UI" || fail "legacy Hook false label not renamed"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"
# New ad module has its own diagnostic-only contract; legacy MainHook's unrelated setResult hooks are out of scope.
# The legacy hook list contains package names/UID blocking config, not scripts.
grep -q "var ext=scope==='scriptList'?'.js':'.txt'" "$UI" || fail "hook list export must stay text, not a fake JavaScript script"
grep -q "var fext=scope==='scriptList'?'.js':'.txt'" "$UI" || fail "multi-export extension must stay text for UID hook list"
echo "PASS: FX target list is separated, sanitized, and gated for LSPosed Hook"

# LSPosed target management is native-only. Keep unrelated UID network blocking.
APP_HOOK_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$APP_HOOK_UI" ] || fail "native FX Hook Activity source missing"
grep -q '应用网络阻断（UID）' "$UI" || fail "separate UID network-blocking UI was removed"
grep -Fq 'String[] labels = {"VPN", "Ad", "隐私", "脚本", "Hook", "设置"};' "$APP_HOOK_UI" || fail "native six-tab Hook navigation missing"
grep -Fq 'section("自定义 Hook")' "$APP_HOOK_UI" || fail "native per-app custom Hook editor missing"
grep -Fq '会员诊断仅记录应用内可观察状态' "$APP_HOOK_UI" || fail "native membership diagnostics must remain read-only"
grep -Fq 'toggle("清理图片/视频元数据", "exif_strip"' "$APP_HOOK_UI" || fail "native EXIF privacy option missing"
grep -Fq 'toggle("阻止剪贴板读取", "clipboard_read_block"' "$APP_HOOK_UI" || fail "native clipboard privacy option missing"
grep -Fq 'DeveloperHookRule.parse' "$APP_HOOK_UI" || fail "native custom Hook descriptor validation missing"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"

# LSPosed target management is native-only. Keep unrelated UID network blocking.
APP_HOOK_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$APP_HOOK_UI" ] || fail "native FX Hook Activity source missing"
grep -q '应用网络阻断（UID）' "$UI" || fail "separate UID network-blocking UI was removed"
grep -Fq 'String[] labels = {"VPN", "Ad", "隐私", "脚本", "Hook", "设置"};' "$APP_HOOK_UI" || fail "native six-tab Hook navigation missing"
grep -Fq 'section("自定义 Hook")' "$APP_HOOK_UI" || fail "native per-app custom Hook editor missing"
grep -Fq '会员诊断仅记录应用内可观察状态' "$APP_HOOK_UI" || fail "native membership diagnostics must remain read-only"
grep -Fq 'toggle("清理图片/视频元数据", "exif_strip"' "$APP_HOOK_UI" || fail "native EXIF privacy option missing"
grep -Fq 'toggle("阻止剪贴板读取", "clipboard_read_block"' "$APP_HOOK_UI" || fail "native clipboard privacy option missing"
grep -Fq 'DeveloperHookRule.parse' "$APP_HOOK_UI" || fail "native custom Hook descriptor validation missing"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"

# LSPosed target management is native-only. Keep unrelated UID network blocking.
APP_HOOK_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$APP_HOOK_UI" ] || fail "native FX Hook Activity source missing"
grep -q '应用网络阻断（UID）' "$UI" || fail "separate UID network-blocking UI was removed"
grep -Fq 'String[] labels = {"VPN", "Ad", "隐私", "脚本", "Hook", "设置"};' "$APP_HOOK_UI" || fail "native six-tab Hook navigation missing"
grep -Fq 'section("自定义 Hook")' "$APP_HOOK_UI" || fail "native per-app custom Hook editor missing"
grep -Fq '会员诊断仅记录应用内可观察状态' "$APP_HOOK_UI" || fail "native membership diagnostics must remain read-only"
grep -Fq 'toggle("清理图片/视频元数据", "exif_strip"' "$APP_HOOK_UI" || fail "native EXIF privacy option missing"
grep -Fq 'toggle("阻止剪贴板读取", "clipboard_read_block"' "$APP_HOOK_UI" || fail "native clipboard privacy option missing"
grep -Fq 'DeveloperHookRule.parse' "$APP_HOOK_UI" || fail "native custom Hook descriptor validation missing"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"

# LSPosed target management is native-only. Keep unrelated UID network blocking.
APP_HOOK_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$APP_HOOK_UI" ] || fail "native FX Hook Activity source missing"
! grep -Fq 'id="cardFxAdHook"' "$UI" || fail "duplicate WebUI LSPosed card remains"
! grep -Fq 'fxHookAppList' "$UI" || fail "duplicate WebUI LSPosed app picker remains"
! grep -Fq 'fxHookManage' "$UI" || fail "duplicate WebUI LSPosed manager remains"
grep -q '应用网络阻断（UID）' "$UI" || fail "separate UID network-blocking UI was removed"
grep -Fq 'String[] labels = {"VPN", "Ad", "隐私", "脚本", "Hook", "设置"};' "$APP_HOOK_UI" || fail "native six-tab Hook navigation missing"
grep -Fq 'section("自定义 Hook")' "$APP_HOOK_UI" || fail "native per-app custom Hook editor missing"
grep -Fq '会员诊断仅记录应用内可观察状态' "$APP_HOOK_UI" || fail "native membership diagnostics must remain read-only"
grep -Fq 'toggle("清理图片/视频元数据", "exif_strip"' "$APP_HOOK_UI" || fail "native EXIF privacy option missing"
grep -Fq 'toggle("阻止剪贴板读取", "clipboard_read_block"' "$APP_HOOK_UI" || fail "native clipboard privacy option missing"
grep -Fq 'DeveloperHookRule.parse' "$APP_HOOK_UI" || fail "native custom Hook descriptor validation missing"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"
