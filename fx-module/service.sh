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
PG=/data/adb/privacyguard
mkdir -p "$PG" 2>/dev/null

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

# Hook APK install is isolated from DNS/VPN startup.
if [ -f "$MODDIR/scripts/install_adhook_app.sh" ]; then
  sh "$MODDIR/scripts/install_adhook_app.sh" "$MODDIR" >> "$PG/boot.log" 2>&1
  [ "$?" -ne 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] Hook APK install deferred/failed; main FX startup continues" >> "$PG/boot.log"
fi

if [ ! -f "$PG/settings.conf" ]; then
  if cat "$MODDIR/scripts/default.conf" > "$PG/settings.conf" 2>>"$PG/boot.log"; then
    chmod 660 "$PG/settings.conf"
  else
    echo "[$(date '+%m-%d %H:%M:%S')] boot: default config generation failed" >> "$PG/boot.log"
  fi
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
if [ -x "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  sh "$MODDIR/scripts/vpn-external-watchdog.sh" snapshot "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] external VPN baseline unavailable; safe reconcile on start" >> "$PG/boot.log"
fi
sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1
_rc=$?
if [ "$_rc" -eq 0 ] && [ -x "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  sh "$MODDIR/scripts/vpn-external-watchdog.sh" mark-applied "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] external VPN applied-state commit failed" >> "$PG/boot.log"
fi
[ "$_rc" -gt 0 ] && echo "[$(date '+%m-%d %H:%M:%S')] boot: apply completed with $_rc failures; inspect apply.errors" >> "$PG/boot.log"
if [ -x "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then
  sh "$MODDIR/scripts/vpn-external-watchdog.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "[$(date '+%m-%d %H:%M:%S')] external VPN watcher failed to start" >> "$PG/boot.log"
fi
if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  mkdir -p "$PG/jsruntime" 2>/dev/null
  nohup sh "$MODDIR/scripts/jsruntime/scheduler.sh" >> "$PG/jsruntime/scheduler.log" 2>&1 &
fi
