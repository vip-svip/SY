#!/system/bin/sh
# PrivacyGuard gen_xposed_conf.sh — 从 settings.conf 生成 LSPosed 层配置
# 应用进程无法读取 /data/adb，因此镜像到 /data/local/tmp/privacyguard/
# >>> pg-moddir (auto)
# 兼容相对路径/软链/su 调用：先尝试按 $0 推导，失败再逐级向上找 module.prop
_pg_d=$(dirname "$0" 2>/dev/null)
MODDIR=$(cd "$_pg_d" 2>/dev/null && pwd)
case "$MODDIR" in */scripts) MODDIR=${MODDIR%/scripts} ;; esac
if [ ! -f "$MODDIR/module.prop" ]; then
  _pg_d2=$MODDIR
  _pg_n=0
  while [ -n "$_pg_d2" ] && [ "$_pg_d2" != "/" ] && [ $_pg_n -lt 4 ]; do
    if [ -f "$_pg_d2/module.prop" ]; then MODDIR=$_pg_d2; break; fi
    _pg_d2=$(dirname "$_pg_d2")
    _pg_n=$((_pg_n+1))
  done
fi
PG_MODDIR=$MODDIR
# <<< pg-moddir
. "$MODDIR/scripts/util.sh"

XDIR=${PG_XPOSED_DIR:-/data/local/tmp/privacyguard}
if ! mkdir -p "$XDIR"; then
  echo "gen_xposed_conf: cannot create $XDIR" >&2
  exit 1
fi
_GXC_SETTINGS_TMP="$XDIR/settings.conf.tmp.$$"
_GXC_XPOSED_TMP="$XDIR/xposed.conf.tmp.$$"
trap 'rm -f "$_GXC_SETTINGS_TMP" "$_GXC_XPOSED_TMP"' EXIT HUP INT TERM

# ---- 配置迁移（升级用户）----
# v1.10.5 新增 lsposed_profile 键。旧版 settings.conf 没有它，若放任不管，
# 13 个破坏性 Hook 会按旧默认值(1)生效 —— 用户一旦在 LSPosed 里勾选普通
# App，该 App 可能出现功能异常甚至闪退（block_process_list 返回空列表 →
# list.get(0) 崩；File.exists 返回 false → 存储检测失败等）。
# 这里在 apply 时幂等补一个安全的默认值，不覆盖用户已显式设置的值。
if [ -f "$CONF" ] && ! grep -q '^lsposed_profile=' "$CONF" 2>/dev/null; then
  _gxc_tmp="$PG/settings.conf.pfmig.$$"
  awk '
    !done && /^lsposed_enabled=/ {
      print
      print "# Hook 档位（LSPosed 层）: compat=零破坏(默认) / standard=仅隐藏root痕迹 / aggressive=全部破坏性Hook"
      print "lsposed_profile=compat"
      done = 1
      next
    }
    { print }
  ' "$CONF" > "$_gxc_tmp" 2>/dev/null
  if [ -s "$_gxc_tmp" ] && [ "$(wc -l < "$_gxc_tmp" 2>/dev/null || echo 0)" -gt 10 ] \
     && grep -q '^lsposed_profile=compat' "$_gxc_tmp" 2>/dev/null; then
    cp -f "$CONF" "$PG/settings.conf.bak.$(date +%s)" 2>/dev/null
    mv -f "$_gxc_tmp" "$CONF" 2>/dev/null && chmod 660 "$CONF" 2>/dev/null
    echo "[$(date '+%m-%d %H:%M:%S')] migrate: 已为旧配置补 lsposed_profile=compat" >> "$PG/apply.log" 2>/dev/null
  else
    rm -f "$_gxc_tmp" 2>/dev/null
  fi
fi

# 完整镜像 settings.conf（包含 conf/list 段）。失败时不能继续发布旧/空 Hook 配置。
if [ ! -s "$CONF" ] || ! cp "$CONF" "$_GXC_SETTINGS_TMP" 2>/dev/null || [ ! -s "$_GXC_SETTINGS_TMP" ]; then
  echo "gen_xposed_conf: settings.conf mirror failed" >&2
  exit 1
fi
chmod 644 "$_GXC_SETTINGS_TMP" 2>/dev/null || exit 1
mv -f "$_GXC_SETTINGS_TMP" "$XDIR/settings.conf" 2>/dev/null || {
  echo "gen_xposed_conf: cannot publish settings.conf" >&2
  exit 1
}

# 先生成临时文件，校验完整后原子发布；不把部分生成的 xposed.conf 当作成功。
: > "$_GXC_XPOSED_TMP" || exit 1
_GXC_WRITE_FAILED=0
emit() {
  echo "$1" >> "$_GXC_XPOSED_TMP" || { _GXC_WRITE_FAILED=1; return 1; }
}

# 开关键直接透传（MainHook 按需读取）——只取第一个 [ 段之前的顶层键
# lsposed_profile 单独处理（下面做合法值校验），这里跳过以免重复行
for k in $(awk '/^\[/{exit} /^[a-z0-9_]+=/{print $0}' "$CONF" | cut -d= -f1); do
  [ "$k" = "lsposed_profile" ] && continue
  v=$(pg_get "$k" 0)
  emit "$k=$v"
done

# ---------- Hook 档位（PART B） ----------
# lsposed_profile 决定「破坏性 Hook」的取值，优先级高于同名逐键开关：
#   compat     = 零破坏（默认）：所有破坏性 Hook 关闭，勾普通 App 不会改变其行为
#   standard   = 仅保留 root 痕迹隐藏，其余破坏性 Hook 关闭
#   aggressive = 全部打开（旧 v1.10.4 逐键全开的效果），仅推荐确定能承受的 App
# 未写该键 / 非法值 → compat：安全默认（零破坏）。
# 旧版（v1.10.4 及以前）没有这个键，若回落到 custom 会让 13 个破坏性 Hook
# 按逐键默认值生效（旧默认还是 1）→ 用户一勾选普通 App 就可能闪退。
# 因此升级用户在没有显式选择时，一律按安全的 compat 处理。
# 注意：不能用 pg_get lsposed_profile ""——util.sh 的 pg_get 是
#   [ -n "$_v" ] && echo "$_v" || echo "${2:-0}"
# `${2:-0}` 对"空字符串"也会回落成 0，于是未设置时拿到的是 "0"（非空），
# 会走进 * 分支。这里直接抓原始值，再判断是否为空。
_pf=$(grep -m1 '^lsposed_profile=' "$CONF" 2>/dev/null | cut -d= -f2- | tr -d ' \r')
case "$_pf" in
  compat|standard|aggressive|custom) emit "lsposed_profile=$_pf" ;;
  *) emit "lsposed_profile=compat" ;;
esac

# 独立应用内 LSPosed Hook 目标列表。它与 [list:hook]（UID 网络阻断）完全分离。
# 行格式：package,splash=1,feed=0,overlay=0,member_diag=1|note|1
# 严格校验包名/字段/布尔值，只发布启用且包含至少一个功能的目标；不执行/求值用户输入。
emit ""
emit "[list:hook_targets]"
pg_list hook_targets 2>/dev/null | awk -F'|' '
  NF >= 3 {
    enabled=$NF; note=$(NF-1); raw=$1
    for (fi=2; fi<=NF-2; fi++) raw=raw "|" $fi
    if (enabled != "1" || raw == "") next
    n=split(raw, a, ",")
    pkg=a[1]
    if (pkg !~ /^[A-Za-z][A-Za-z0-9_]*([.][A-Za-z0-9_]+)+$/ || n < 2) next
    splash=feed=overlay=member=privacy=0; valid=1
    for (i=2; i<=n; i++) {
      eq=index(a[i], "=")
      if (eq < 2) { valid=0; break }
      key=substr(a[i],1,eq-1); val=substr(a[i],eq+1)
      if (key == "dev_hook_enabled" || key ~ /^dev_rule_[0-9]+$/) continue
      if (key == "rules") {
        if (val !~ /^(splash|feed|overlay):[A-Za-z0-9_.-][A-Za-z0-9_.-][A-Za-z0-9_.-]*(;(splash|feed|overlay):[A-Za-z0-9_.-][A-Za-z0-9_.-][A-Za-z0-9_.-]*)*$/) { valid=0; break }
        ruleCount=split(val, ruleParts, ";")
        for (ri=1; ri<=ruleCount; ri++) {
          colon=index(ruleParts[ri], ":")
          token=substr(ruleParts[ri], colon+1)
          if (colon < 2 || length(token) < 3 || length(token) > 100) { valid=0; break }
          for (rj=ri+1; rj<=ruleCount; rj++) {
            if (ruleParts[ri] == ruleParts[rj]) { valid=0; break }
          }
          if (!valid) break
        }
        if (!valid) break
        continue
      }
      if (val != "0" && val != "1") { valid=0; break }
      if (key == "splash") splash=val
      else if (key == "feed") feed=val
      else if (key == "overlay") overlay=val
      else if (key == "member_diag") member=val
      else if (key == "privacy") privacy=val
      else { valid=0; break }
    }
    if (!valid || !(splash+feed+overlay+member+privacy)) next
    note=$2; if (note == "") note="FX LSPosed Hook"
    # Keep legacy MainHook format free of modern-only privacy fields.
    print pkg ",splash=" splash ",feed=" feed ",overlay=" overlay ",member_diag=" member "|" note "|1"
  }
' >> "$_GXC_XPOSED_TMP" || exit 1

# conf 段透传
for sec in clipboard app_list telephony mock_location perapp_mock gps_accuracy \
           spoof_model spoof_manufacturer spoof_version spoof_brand spoof_serial \
           spoof_android_id spoof_imei spoof_sim spoof_fingerprint spoof_hardware \
           spoof_baseband spoof_bt_mac spoof_wifi_mac spoof_storage spoof_screen \
           spoof_battery cam_null mic_block exif_strip audio_fp_block fs_rootlist \
           fs_attrs fs_isolate fs_hide fs_vfs block_notif_listen hide_notif_perm \
           block_ime_logging boot_time_spoof patch_spoof syssvc_hide global_dns vpn \
           lsposed_scope; do
  BODY=$(pg_conf "$sec")
  if [ -n "$BODY" ]; then
    emit ""
    emit "[conf:$sec]"
    echo "$BODY" >> "$_GXC_XPOSED_TMP" || exit 1
  fi
done

if [ "$_GXC_WRITE_FAILED" -ne 0 ] || [ ! -s "$_GXC_XPOSED_TMP" ] || ! grep -q '^lsposed_profile=' "$_GXC_XPOSED_TMP"; then
  echo "gen_xposed_conf: generated Hook config is empty/incomplete" >&2
  exit 1
fi
chmod 644 "$_GXC_XPOSED_TMP" 2>/dev/null || exit 1
mv -f "$_GXC_XPOSED_TMP" "$XDIR/xposed.conf" 2>/dev/null || {
  echo "gen_xposed_conf: cannot publish xposed.conf" >&2
  exit 1
}

# Modern LSPosed target-app processes run as ordinary app UIDs and must not read
# /data/local/tmp or /data/adb directly. Publish only the minimal ad-hook config
# through LSPosed's documented Remote Files location; the hook reads it with
# XposedInterface.openRemoteFile(). Keep the legacy xposed.conf for older hooks.
_GXC_LSPD_ROOT=${PG_LSPOSED_REMOTE_ROOT:-/data/adb/lspd}
_GXC_REMOTE_ROOT="$_GXC_LSPD_ROOT/modules"
_GXC_REMOTE_STATUS="$XDIR/xposed-remote.status"
_GXC_REMOTE_STATUS_TMP="$XDIR/xposed-remote.status.tmp.$$"
_GXC_REMOTE_TARGETS=$(awk '
  /^\[list:hook_targets\]$/ { inlist=1; next }
  /^\[/ { if (inlist) exit }
  inlist && /\|1$/ { n++ }
  END { print n+0 }
' "$XDIR/xposed.conf" 2>/dev/null | tr -d ' ')
_GXC_REMOTE_ENABLED=$(awk '/^\[/{exit} /^hook_ads_enabled=/{sub(/^hook_ads_enabled=/, ""); print; exit}' "$XDIR/xposed.conf" 2>/dev/null | tr -d ' \r')
_GXC_REMOTE_RESULT=framework_missing
if [ -d "$_GXC_LSPD_ROOT" ]; then
  _GXC_REMOTE_RESULT=failed
  _GXC_USERS=$(pm list users 2>/dev/null | sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p' | sort -u | tr '\n' ' ')
  [ -n "$_GXC_USERS" ] || _GXC_USERS=0
  _GXC_ALL_OK=1
  for _gxc_uid in $_GXC_USERS; do
    case "$_gxc_uid" in ''|*[!0-9]*) _GXC_ALL_OK=0; continue ;; esac
    _gxc_dir="$_GXC_REMOTE_ROOT/$_gxc_uid/de.privacyguard.adhook/files"
    _gxc_tmp="$_gxc_dir/fx-hook-targets.conf.tmp.$$"
    _gxc_final="$_gxc_dir/fx-hook-targets.conf"
    if ! mkdir -p "$_gxc_dir" 2>/dev/null; then
      echo "gen_xposed_conf: cannot create LSPosed Remote Files dir for user $_gxc_uid" >&2
      _GXC_ALL_OK=0
      continue
    fi
    _GXC_NATIVE_CONFIG="$PG/fx-native-hook-targets-$_gxc_uid.conf"
    if [ -e "$_GXC_NATIVE_CONFIG" ]; then
      _GXC_NATIVE_SIZE=$(wc -c < "$_GXC_NATIVE_CONFIG" 2>/dev/null | tr -d ' ')
      _GXC_NATIVE_LINES=$(wc -l < "$_GXC_NATIVE_CONFIG" 2>/dev/null | tr -d ' ')
      if [ ! -f "$_GXC_NATIVE_CONFIG" ] || [ -L "$_GXC_NATIVE_CONFIG" ] ||
         [ ! -s "$_GXC_NATIVE_CONFIG" ] || [ "${_GXC_NATIVE_SIZE:-0}" -gt 65536 ] ||
         [ "${_GXC_NATIVE_LINES:-0}" -gt 1000 ] ||
         ! grep -q '^schema_version=1$' "$_GXC_NATIVE_CONFIG" ||
         ! grep -q '^ads_enabled=[01]$' "$_GXC_NATIVE_CONFIG" ||
         ! grep -q '^privacy_enabled=[01]$' "$_GXC_NATIVE_CONFIG" ||
         ! grep -q '^\[list:targets\]$' "$_GXC_NATIVE_CONFIG"; then
        echo "gen_xposed_conf: native Hook overlay invalid for user $_gxc_uid; refusing to overwrite it with legacy config" >&2
        _GXC_ALL_OK=0
        continue
      fi
      if ! cp "$_GXC_NATIVE_CONFIG" "$_gxc_tmp" 2>/dev/null || [ ! -s "$_gxc_tmp" ]; then
        echo "gen_xposed_conf: native Hook overlay copy failed for user $_gxc_uid" >&2
        rm -f "$_gxc_tmp" 2>/dev/null
        _GXC_ALL_OK=0
        continue
      fi
      _GXC_REMOTE_ENABLED=$(awk '/^\[/{exit} /^ads_enabled=/{sub(/^ads_enabled=/, ""); print; exit}' "$_gxc_tmp" | tr -d ' \r')
      _GXC_REMOTE_TARGETS=$(awk '/^\[list:targets\]$/ {inlist=1; next} /^\[/ {if (inlist) exit} inlist && NF {n++} END {print n+0}' "$_gxc_tmp" | tr -d ' ')
    else
    {
      # Modern unified Hook schema. Keep xposed.conf in its legacy format for
      # existing MainHook consumers; translate only the Remote Files payload.
      _gxc_ads=$(awk '/^\[/{exit} /^hook_ads_enabled=/{sub(/^hook_ads_enabled=/, ""); print; exit}' "$XDIR/xposed.conf" | tr -d ' \r')
      case "$_gxc_ads" in 0|1) ;; *) _gxc_ads=0 ;; esac
      _gxc_privacy=$(awk '/^\[/{exit} /^hook_privacy_enabled=/{sub(/^hook_privacy_enabled=/, ""); print; exit}' "$XDIR/xposed.conf" | tr -d ' \r')
      case "$_gxc_privacy" in 0|1) ;; *) _gxc_privacy=0 ;; esac
      echo "schema_version=1"
      echo "ads_enabled=$_gxc_ads"
      echo "privacy_enabled=$_gxc_privacy"
      _gxc_wifi_scan=$(awk '/^\[/{exit} /^block_wifi_scan=/{sub(/^block_wifi_scan=/, ""); print; exit}' "$XDIR/xposed.conf" | tr -d ' \r')
      case "$_gxc_wifi_scan" in 0|1) ;; *) _gxc_wifi_scan=0 ;; esac
      echo "wifi_scan_enabled=$_gxc_wifi_scan"
      _gxc_notification_listen=$(awk '/^\[/{exit} /^block_notif_listen=/{sub(/^block_notif_listen=/, ""); print; exit}' "$XDIR/xposed.conf" | tr -d ' \r')
      case "$_gxc_notification_listen" in 0|1) ;; *) _gxc_notification_listen=0 ;; esac
      echo "notification_listen_enabled=$_gxc_notification_listen"
      _gxc_notification_permission_hide=$(awk '/^\[/{exit} /^hide_notif_perm=/{sub(/^hide_notif_perm=/, ""); print; exit}' "$XDIR/xposed.conf" | tr -d ' \r')
      case "$_gxc_notification_permission_hide" in 0|1) ;; *) _gxc_notification_permission_hide=0 ;; esac
      echo "notification_permission_hide_enabled=$_gxc_notification_permission_hide"
      _gxc_clipboard_isolate=$(awk '/^\[/{exit} /^clipboard_isolate=/{sub(/^clipboard_isolate=/, ""); print; exit}' "$XDIR/xposed.conf" | tr -d ' \r')
      case "$_gxc_clipboard_isolate" in 0|1) ;; *) _gxc_clipboard_isolate=0 ;; esac
      echo "clipboard_isolate_enabled=$_gxc_clipboard_isolate"
      echo ""
      echo "[list:targets]"
      awk -F'|' '
        /^\[list:hook_targets\]$/ { inlist=1; next }
        /^\[/ { if (inlist) exit }
        inlist && $0 !~ /^[[:space:]]*#/ && NF >= 3 {
          enabled=$NF; note=$(NF-1); line=$1
          for (fi=2; fi<=NF-2; fi++) line=line "|" $fi
          if (enabled != "1" || line == "") next
          n=split(line,a,",")
          if (n < 2) next
          pkg=a[1]; splash=feed=overlay=member=privacy=exif=clipboard=0
          sensor_accel=sensor_gyro=sensor_light=sensor_magnet=sensor_pressure=sensor_prox=sensor_rate_limit=0; wifi_scan=0; notification_listen=0; notification_permission_hide=0; clipboard_isolate=0; mic_silence=0
          camera_access=0; location_access=0; mic_access=0; media_store_query=0
          rules=""; dev_enabled=0; dev_rule_count=0; dev_rules=""; dev_seen_ids=""; valid=1
          if (pkg !~ /^[A-Za-z][A-Za-z0-9_]*([.][A-Za-z0-9_]+)+$/) next
          for (i=2;i<=n;i++) {
            eq=index(a[i], "=")
            if (eq < 2) { valid=0; break }
            key=substr(a[i],1,eq-1); val=substr(a[i],eq+1)
            if (key == "rules") {
              if (val !~ /^(splash|feed|overlay):[A-Za-z0-9_.-][A-Za-z0-9_.-][A-Za-z0-9_.-]*(;(splash|feed|overlay):[A-Za-z0-9_.-][A-Za-z0-9_.-][A-Za-z0-9_.-]*)*$/) { valid=0; break }
              ruleCount=split(val, ruleParts, ";")
              for (ri=1; ri<=ruleCount; ri++) {
                colon=index(ruleParts[ri], ":")
                token=substr(ruleParts[ri], colon+1)
                if (colon < 2 || length(token) < 3 || length(token) > 100) { valid=0; break }
                for (rj=ri+1; rj<=ruleCount; rj++) {
                  if (ruleParts[ri] == ruleParts[rj]) { valid=0; break }
                }
                if (!valid) break
              }
              if (!valid) break
              rules=val; continue
            }
            if (key == "dev_hook_enabled") {
              if (val != "0" && val != "1") { valid=0; break }
              dev_enabled=val; continue
            }
            if (key ~ /^dev_rule_[1-9][0-9]?$/) {
              rule_number=substr(key,10)+0
              if (rule_number < 1 || rule_number > 64 || dev_rule_count >= 64) { valid=0; break }
              nfields=split(val, dev_parts, "|")
              if (nfields != 4 || dev_parts[1] !~ /^[A-Za-z][A-Za-z0-9_-]{0,31}$/ ||
                  dev_parts[2] !~ /^L[A-Za-z_$][A-Za-z0-9_$/]*;->[A-Za-z_$<>][A-Za-z0-9_$<>]*\(.*\).+$/ ||
                  (dev_parts[3] != "OBSERVE" && dev_parts[3] != "DISABLED" && dev_parts[3] != "RETURN_TRUE" && dev_parts[3] != "RETURN_FALSE") ||
                  dev_parts[4] !~ /^-?[0-9]+$/ || dev_parts[4] < -1000 || dev_parts[4] > 1000) { valid=0; break }
              if (index(dev_seen_ids, "|" dev_parts[1] "|") > 0) { valid=0; break }
              dev_seen_ids=dev_seen_ids "|" dev_parts[1] "|"
              dev_rule_count++
              dev_rules=dev_rules sprintf(",dev_rule_%d=%s", dev_rule_count, val)
              continue
            }
            if (val != "0" && val != "1") { valid=0; break }
            if (key == "splash") splash=val
            else if (key == "feed") feed=val
            else if (key == "overlay") overlay=val
            else if (key == "member_diag") member=val
            else if (key == "privacy") privacy=val
            else if (key == "exif_strip") exif=val
            else if (key == "clipboard_read_block") clipboard=val
            else if (key == "clipboard_isolate") clipboard_isolate=val
            else if (key == "sensor_accel") sensor_accel=val
            else if (key == "sensor_gyro") sensor_gyro=val
            else if (key == "sensor_light") sensor_light=val
            else if (key == "sensor_magnet") sensor_magnet=val
            else if (key == "sensor_pressure") sensor_pressure=val
            else if (key == "sensor_prox") sensor_prox=val
            else if (key == "sensor_rate_limit") sensor_rate_limit=val
            else if (key == "wifi_scan_block") wifi_scan=val
            else if (key == "notification_listen_block") notification_listen=val
            else if (key == "notification_permission_hide_block") notification_permission_hide=val
            else if (key == "mic_silence") mic_silence=val
            else if (key == "camera_access_block") camera_access=val
            else if (key == "location_access_block") location_access=val
            else if (key == "mic_access_block") mic_access=val
            else if (key == "media_store_query_block") media_store_query=val
            else { valid=0; break }
          }
          if (rules != "") {
            ruleCount=split(rules, ruleParts, ";")
            for (ri=1; ri<=ruleCount; ri++) {
              colon=index(ruleParts[ri], ":")
              ruleCategory=substr(ruleParts[ri], 1, colon-1)
              if ((ruleCategory == "splash" && splash != 1) ||
                  (ruleCategory == "feed" && feed != 1) ||
                  (ruleCategory == "overlay" && overlay != 1)) { valid=0; break }
            }
          }
          # Developer-defined method hooks are not implemented by the current Android
          # UnifiedHookConfigParser. Do not let unsupported keys invalidate the
          # complete Remote Files payload; omit targets that only request them.
          if (!valid || (clipboard && clipboard_isolate) || (!(splash+feed+overlay+member+privacy+exif+clipboard+clipboard_isolate+sensor_accel+sensor_gyro+sensor_light+sensor_magnet+sensor_pressure+sensor_prox+sensor_rate_limit+wifi_scan+notification_listen+notification_permission_hide+mic_silence+camera_access+location_access+mic_access+media_store_query) && rules == "")) next
          printf "%s,ads_splash=%s,ads_feed=%s,ads_overlay=%s,member_diag=%s,privacy=%s,exif_strip=%s,clipboard_read_block=%s,clipboard_isolate=%s,sensor_accel=%s,sensor_gyro=%s,sensor_light=%s,sensor_magnet=%s,sensor_pressure=%s,sensor_prox=%s,sensor_rate_limit=%s,wifi_scan_block=%s,notification_listen_block=%s,notification_permission_hide=%s,mic_silence=%s,camera_access_block=%s,location_access_block=%s,mic_access_block=%s,media_store_query_block=%s", pkg,splash,feed,overlay,member,privacy,exif,clipboard,clipboard_isolate,sensor_accel,sensor_gyro,sensor_light,sensor_magnet,sensor_pressure,sensor_prox,sensor_rate_limit,wifi_scan,notification_listen,notification_permission_hide,mic_silence,camera_access,location_access,mic_access,media_store_query
          if (rules != "") printf ",rules=%s", rules
          printf "\n"
        }
      ' "$XDIR/settings.conf"
    } > "$_gxc_tmp" 2>/dev/null || { rm -f "$_gxc_tmp"; _GXC_ALL_OK=0; continue; }
    fi
    if [ ! -s "$_gxc_tmp" ] || ! grep -q '^schema_version=1$' "$_gxc_tmp" || ! grep -q '^ads_enabled=' "$_gxc_tmp" || ! grep -q '^privacy_enabled=' "$_gxc_tmp" || ! grep -q '^notification_permission_hide_enabled=' "$_gxc_tmp" || ! grep -q '^clipboard_isolate_enabled=' "$_gxc_tmp" || ! grep -q '^\[list:targets\]$' "$_gxc_tmp"; then
      rm -f "$_gxc_tmp" 2>/dev/null
      _GXC_ALL_OK=0
      continue
    fi
    chmod 0644 "$_gxc_tmp" 2>/dev/null || { rm -f "$_gxc_tmp"; _GXC_ALL_OK=0; continue; }
    chown 0:0 "$_gxc_tmp" 2>/dev/null || { rm -f "$_gxc_tmp"; _GXC_ALL_OK=0; continue; }
    # LSPosed creates its Remote Files under magisk_file; label explicitly because
    # this publisher may create the directory before the framework does.
    if ! chcon u:object_r:magisk_file:s0 "$_gxc_dir" "$_gxc_tmp" 2>/dev/null; then
      rm -f "$_gxc_tmp" 2>/dev/null
      echo "gen_xposed_conf: SELinux label failed for Remote Files user $_gxc_uid" >&2
      _GXC_ALL_OK=0
      continue
    fi
    if ! mv -f "$_gxc_tmp" "$_gxc_final" 2>/dev/null; then
      rm -f "$_gxc_tmp" 2>/dev/null
      _GXC_ALL_OK=0
      continue
    fi
    chmod 0644 "$_gxc_final" 2>/dev/null || _GXC_ALL_OK=0
    chown 0:0 "$_gxc_final" 2>/dev/null || _GXC_ALL_OK=0
    chcon u:object_r:magisk_file:s0 "$_gxc_dir" "$_gxc_final" 2>/dev/null || _GXC_ALL_OK=0
    if [ "$_GXC_ALL_OK" -eq 1 ]; then
      echo "[$(date '+%m-%d %H:%M:%S')] gen_xposed_conf: LSPosed Remote Files published for user $_gxc_uid, targets=$_GXC_REMOTE_TARGETS enabled=$_GXC_REMOTE_ENABLED" >> "$PG/apply.log" 2>/dev/null
    fi
  done
  [ "$_GXC_ALL_OK" -eq 1 ] && _GXC_REMOTE_RESULT=ok
  # Publication is a multi-user transaction: if any user fails, remove every
  # modern payload already published in this pass so no user keeps stale or
  # partially updated rules while status reports failure.
  if [ "$_GXC_ALL_OK" -ne 1 ]; then
    for _gxc_uid in $_GXC_USERS; do
      case "$_gxc_uid" in ''|*[!0-9]*) continue ;; esac
      _gxc_dir="$_GXC_REMOTE_ROOT/$_gxc_uid/de.privacyguard.adhook/files"
      rm -f "$_gxc_dir/fx-hook-targets.conf" "$_gxc_dir"/fx-hook-targets.conf.tmp.* 2>/dev/null
    done
    echo "gen_xposed_conf: partial Remote Files publication rolled back for all users" >&2
    echo "[$(date '+%m-%d %H:%M:%S')] gen_xposed_conf: partial Remote Files publication rolled back for all users" >> "$PG/apply.log" 2>/dev/null
  fi
fi
if ! {
  echo "status=$_GXC_REMOTE_RESULT"
  echo "enabled=${_GXC_REMOTE_ENABLED:-0}"
  echo "targets=${_GXC_REMOTE_TARGETS:-0}"
  echo "updated=$(date +%s 2>/dev/null || echo 0)"
} > "$_GXC_REMOTE_STATUS_TMP" 2>/dev/null; then
  rm -f "$_GXC_REMOTE_STATUS_TMP" "$_GXC_REMOTE_STATUS" 2>/dev/null
  echo "gen_xposed_conf: cannot write Remote Files status; removed stale status" >&2
  exit 1
fi
if ! chmod 0600 "$_GXC_REMOTE_STATUS_TMP" 2>/dev/null || ! mv -f "$_GXC_REMOTE_STATUS_TMP" "$_GXC_REMOTE_STATUS" 2>/dev/null; then
  rm -f "$_GXC_REMOTE_STATUS_TMP" "$_GXC_REMOTE_STATUS" 2>/dev/null
  echo "gen_xposed_conf: cannot publish Remote Files status; removed stale status" >&2
  exit 1
fi
if [ "$_GXC_REMOTE_RESULT" = "failed" ]; then
  # The caller consumes xposed-remote.status and records the apply failure.
  # Return success here only to mean the diagnostic status was recorded; it
  # must not be interpreted as successful publication.
  echo "gen_xposed_conf: LSPosed Remote Files publish failed; app hook will remain inactive" >&2
fi
# Local settings mirrors are intentionally shell-readable for the legacy root bridge;
# modern target-app hooks never access this directory directly.
chcon u:object_r:shell_data_file:s0 "$XDIR/xposed.conf" "$XDIR/settings.conf" "$XDIR/xposed-remote.status" 2>/dev/null || true
exit 0
