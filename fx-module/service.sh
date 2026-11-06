#!/system/bin/sh
# PrivacyGuard 开机服务：等待启动完成后应用配置
# >>> pg-moddir (auto)
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
# >>> fx-service-state-dir-guard
pg_path_components_are_safe() {
  _pg_path=$1
  case "$_pg_path" in /*) : ;; *) return 1 ;; esac
  case "$_pg_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _pg_rest=${_pg_path#/}
  _pg_current=
  while [ -n "$_pg_rest" ]; do
    case "$_pg_rest" in
      */*) _pg_part=${_pg_rest%%/*}; _pg_rest=${_pg_rest#*/} ;;
      *) _pg_part=$_pg_rest; _pg_rest= ;;
    esac
    case "$_pg_part" in ''|.|..) return 1 ;; esac
    _pg_current="$_pg_current/$_pg_part"
    [ ! -L "$_pg_current" ] || return 1
  done
  return 0
}
pg_ensure_state_dir() {
  _pg_state_dir=$1
  pg_path_components_are_safe "$_pg_state_dir" || return 1
  _pg_parent=${_pg_state_dir%/*}
  [ -n "$_pg_parent" ] || _pg_parent=/
  [ -d "$_pg_parent" ] && [ ! -L "$_pg_parent" ] || return 1
  if [ -e "$_pg_state_dir" ]; then
    [ -d "$_pg_state_dir" ] && [ ! -L "$_pg_state_dir" ] || return 1
  else
    (umask 077; mkdir "$_pg_state_dir") || return 1
  fi
  pg_path_components_are_safe "$_pg_state_dir" &&
    [ -d "$_pg_state_dir" ] && [ ! -L "$_pg_state_dir" ]
}
# <<< fx-service-state-dir-guard

PG=/data/adb/privacyguard
if ! pg_ensure_state_dir "$PG"; then
  echo "FX boot service: refusing unsafe or unavailable private state directory" >&2
  exit 1
fi

# ZIP extraction can preserve an overly restrictive mode on the bundled ARM64 QuickJS.
# Repair it before any later runtime task is started; failure is logged and does not
# block DNS/VPN startup.
_QJS_BIN="$MODDIR/bin/arm64/qjs"
if [ -f "$_QJS_BIN" ]; then
  chmod 0755 "$_QJS_BIN" 2>/dev/null || :
  if [ ! -x "$_QJS_BIN" ]; then
    echo "[$(date '+%m-%d %H:%M:%S')] QuickJS: bundled qjs is present but still not executable after chmod" >> "$PG/boot.log"
  else
    echo "[$(date '+%m-%d %H:%M:%S')] QuickJS: executable permission verified" >> "$PG/boot.log"
  fi
fi

pg_ca_boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null; }
pg_ca_mark_synced() {
  _pcm_id=$(pg_ca_boot_id)
  [ -n "$_pcm_id" ] || return 1
  _pcm_tmp="$PG/ca-sync-boot-id.tmp.$$"
  (umask 077; printf '%s\n' "$_pcm_id" > "$_pcm_tmp") && \
    chmod 600 "$_pcm_tmp" 2>/dev/null && mv -f "$_pcm_tmp" "$PG/ca-sync-boot-id" 2>/dev/null || { rm -f "$_pcm_tmp" 2>/dev/null; return 1; }
  _pcm_pending=$(cat "$PG/cacerts-skipmount-pending" 2>/dev/null)
  if [ -f "$PG/cacerts-skipmount-pending" ] && [ -n "$_pcm_pending" ] && [ "$_pcm_pending" != "$_pcm_id" ]; then
    rm -f "$PG/cacerts-skipmount-pending" 2>/dev/null
    echo "[$(date '+%m-%d %H:%M:%S')] CA: previous-boot child skip_mount migration completed" >> "$PG/boot.log"
  fi
}
pg_ca_synced_this_boot() {
  _pcs_id=$(pg_ca_boot_id)
  [ -n "$_pcs_id" ] && [ "$(cat "$PG/ca-sync-boot-id" 2>/dev/null)" = "$_pcs_id" ]
}

# Android 14+: sync trust only after explicit user opt-in.
_PG_CA_SYNC_EARLY_OK=0
_PG_CA_API=$(getprop ro.build.version.sdk 2>/dev/null)
case "$_PG_CA_API" in ''|*[!0-9]*) _PG_CA_API=0 ;; esac
if [ "$_PG_CA_API" -ge 34 ] && [ -f "$PG/ca-trust-optin" ] && [ -f "$MODDIR/scripts/certmgr.sh" ]; then
  _ca_wait=0
  while [ -z "$(pidof zygote 2>/dev/null)$(pidof zygote64 2>/dev/null)" ] && [ "$_ca_wait" -lt 60 ]; do
    sleep 1
    _ca_wait=$((_ca_wait+1))
  done
  if [ -n "$(pidof zygote 2>/dev/null)$(pidof zygote64 2>/dev/null)" ]; then
    if sh "$MODDIR/scripts/certmgr.sh" builtin sync >> "$PG/boot.log" 2>&1 && pg_ca_mark_synced; then
      _PG_CA_SYNC_EARLY_OK=1
      echo "[$(date '+%m-%d %H:%M:%S')] CA: APEX trust synchronized after zygote became available" >> "$PG/boot.log"
    else
      echo "[$(date '+%m-%d %H:%M:%S')] CA: early APEX trust sync failed; retrying after boot completion" >> "$PG/boot.log"
    fi
  else
    echo "[$(date '+%m-%d %H:%M:%S')] CA: zygote not found within 60s; trust sync deferred" >> "$PG/boot.log"
  fi
fi

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do
  sleep 2
  i=$((i + 1))
done
[ "$(getprop sys.boot_completed)" != "1" ] && echo "[$(date '+%m-%d %H:%M:%S')] boot: sys.boot_completed timeout (120s); applying config anyway" >> "$PG/boot.log"

# Hook APK PackageManager work must not race the system-app scan. The
# systemless /system/app overlay was already verified/labeled by post-fs-data;
# if Android has not completed boot, defer PM work to the next boot service
# invocation rather than downgrading or racing an incomplete package scan.
if [ "$(getprop sys.boot_completed)" = "1" ]; then
  if [ -f "$MODDIR/scripts/install_adhook_app.sh" ]; then
    sh "$MODDIR/scripts/install_adhook_app.sh" "$MODDIR" >> "$PG/boot.log" 2>&1
    [ "$?" -ne 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] Hook APK install deferred/failed; main FX startup continues" >> "$PG/boot.log"
  fi
else
  echo "[$(date '+%m-%d %H:%M:%S')] Hook APK PackageManager work deferred: sys.boot_completed is not 1; main FX startup continues" >> "$PG/boot.log"
fi

# settings.conf is the shared source of truth for DNS, VPN and Hosts.
# Never follow a pre-existing symlink, and never expose a partially copied
# default file if storage fills or the boot service is interrupted.
_pg_settings="$PG/settings.conf"
_pg_defaults="$MODDIR/scripts/default.conf"
if [ -L "$_pg_settings" ] || { [ -e "$_pg_settings" ] && [ ! -f "$_pg_settings" ]; }; then
  echo "[$(date '+%m-%d %H:%M:%S')] boot: refusing unsafe settings.conf path" >> "$PG/boot.log"
  exit 1
fi
if [ ! -e "$_pg_settings" ]; then
  if [ ! -f "$_pg_defaults" ] || [ -L "$_pg_defaults" ] || [ ! -r "$_pg_defaults" ]; then
    echo "[$(date '+%m-%d %H:%M:%S')] boot: bundled default config is missing or unsafe" >> "$PG/boot.log"
    exit 1
  fi
  _pg_settings_tmp=$(umask 077; mktemp "$PG/settings.conf.init.XXXXXX") || {
    echo "[$(date '+%m-%d %H:%M:%S')] boot: cannot stage default settings" >> "$PG/boot.log"
    exit 1
  }
  if ! cat "$_pg_defaults" > "$_pg_settings_tmp" ||
      [ ! -s "$_pg_settings_tmp" ] ||
      ! chmod 660 "$_pg_settings_tmp"; then
    rm -f "$_pg_settings_tmp" 2>/dev/null
    echo "[$(date '+%m-%d %H:%M:%S')] boot: default config staging failed" >> "$PG/boot.log"
    exit 1
  fi
  # Another boot worker may have won initialization. Never replace its file.
  if [ -e "$_pg_settings" ] || [ -L "$_pg_settings" ]; then
    rm -f "$_pg_settings_tmp" 2>/dev/null
  elif ! mv -f "$_pg_settings_tmp" "$_pg_settings"; then
    rm -f "$_pg_settings_tmp" 2>/dev/null
    echo "[$(date '+%m-%d %H:%M:%S')] boot: atomic default config publication failed" >> "$PG/boot.log"
    exit 1
  fi
fi
if [ -L "$_pg_settings" ] || [ ! -f "$_pg_settings" ] || [ ! -s "$_pg_settings" ] || [ ! -r "$_pg_settings" ]; then
  echo "[$(date '+%m-%d %H:%M:%S')] boot: settings.conf is unavailable or unsafe; refusing runtime apply" >> "$PG/boot.log"
  exit 1
fi

if [ -f "$PG/ca-trust-optin" ] && [ -f "$MODDIR/scripts/certmgr.sh" ]; then
  if [ "$_PG_CA_SYNC_EARLY_OK" = 1 ] || pg_ca_synced_this_boot; then
    echo "[$(date '+%m-%d %H:%M:%S')] boot: CA trust already synchronized this boot" >> "$PG/boot.log"
  elif sh "$MODDIR/scripts/certmgr.sh" builtin sync >> "$PG/boot.log" 2>&1; then
    pg_ca_mark_synced || echo "[$(date '+%m-%d %H:%M:%S')] boot: unable to persist CA sync marker" >> "$PG/boot.log"
  else
    echo "[$(date '+%m-%d %H:%M:%S')] boot: CA trust sync failed; no new CA auto-enabled" >> "$PG/boot.log"
  fi
fi

[ -f "$MODDIR/scripts/vpn-auto-update.sh" ] && sh "$MODDIR/scripts/vpn-auto-update.sh" "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1
if [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  sh "$MODDIR/scripts/vpn-external-watchdog.sh" snapshot "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] external VPN baseline unavailable; safe reconcile on start" >> "$PG/boot.log"
fi
sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1
_rc=$?
# Root Proxy whitelist reconciliation follows PackageManager changes even when the APK UI is not foreground.
if [ -f "$MODDIR/scripts/yulong-root-proxy-package-watch.sh" ]; then
  sh "$MODDIR/scripts/yulong-root-proxy-package-watch.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || \\
    echo "[$(date '+%m-%d %H:%M:%S')] Root Proxy package watcher failed to start" >> "$PG/boot.log"
fi
if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" apply >> "$PG/boot.log" 2>&1 || \
    echo "[$(date '+%m-%d %H:%M:%S')] Yulong per-app firewall deferred; FX main startup continues" >> "$PG/boot.log"
fi
if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" start-watch >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] Yulong local-time firewall watcher failed to start" >> "$PG/boot.log"
fi
# The Yulong 7.0.1 schedule is a module-owned watcher. It only toggles the
# Yulong ad-filter master bit and is safe to start after FX apply reconciles.
if [ -f "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-ad-schedule.sh" start >> "$PG/boot.log" 2>&1 || \
    echo "[$(date '+%m-%d %H:%M:%S')] Yulong ad schedule watcher failed to start" >> "$PG/boot.log"
fi
if [ "$_rc" -eq 0 ] && [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  sh "$MODDIR/scripts/vpn-external-watchdog.sh" mark-applied "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] external VPN applied-state commit failed" >> "$PG/boot.log"
fi
[ "$_rc" -gt 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] boot: apply completed with $_rc failures; inspect apply.errors" >> "$PG/boot.log"
if [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  sh "$MODDIR/scripts/vpn-external-watchdog.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] external VPN watcher failed to start" >> "$PG/boot.log"
fi
if [ -x "$MODDIR/scripts/yulong-trusted-network.sh" ]; then
  sh "$MODDIR/scripts/yulong-trusted-network.sh" start >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] Yulong trusted-network watcher failed to start" >> "$PG/boot.log"
fi
if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  mkdir -p "$PG/jsruntime" 2>/dev/null
  nohup sh "$MODDIR/scripts/jsruntime/scheduler.sh" >> "$PG/jsruntime/scheduler.log" 2>&1 &
fi
