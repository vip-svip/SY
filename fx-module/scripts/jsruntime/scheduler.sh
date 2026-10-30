#!/system/bin/sh
# Hourly watcher for enabled script subscriptions; configured cadence is in settings.conf.
set -u
_d=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)
MODDIR=$(CDPATH= cd -- "$_d/../.." 2>/dev/null && pwd)
[ -f "$MODDIR/module.prop" ] || exit 2
PG=/data/adb/privacyguard
mkdir -p "$PG/jsruntime" 2>/dev/null || exit 1
PIDFILE="$PG/jsruntime/scheduler.pid"
if [ -f "$PIDFILE" ]; then
  old=$(cat "$PIDFILE" 2>/dev/null)
  case "$old" in ''|*[!0-9]*) old= ;; esac
  if [ -n "$old" ] && [ -r "/proc/$old/cmdline" ] && tr '\000' ' ' < "/proc/$old/cmdline" | grep -F "$MODDIR/scripts/jsruntime/scheduler.sh" >/dev/null 2>&1; then exit 0; fi
fi
printf '%s\n' "$$" > "$PIDFILE" || exit 1
chmod 600 "$PIDFILE" 2>/dev/null || :
cleanup() { current=$(cat "$PIDFILE" 2>/dev/null); [ "$current" = "$$" ] && rm -f "$PIDFILE"; }
trap cleanup EXIT HUP INT TERM
while [ -f "$MODDIR/module.prop" ] && [ -f "$PG/settings.conf" ]; do
  interval=$(grep -m1 '^script_auto_update_h=' "$PG/settings.conf" 2>/dev/null | cut -d= -f2- | tr -d ' ')
  interval=${interval:-24}
  case "$interval" in ''|*[!0-9]*) interval=24 ;; esac
  [ "$interval" -lt 1 ] && interval=1; [ "$interval" -gt 168 ] && interval=168
  now=$(date +%s 2>/dev/null); case "$now" in ''|*[!0-9]*) now=0 ;; esac
  stamp="$PG/jsruntime/sub-last"; prev=0; [ -f "$stamp" ] && prev=$(cat "$stamp" 2>/dev/null)
  case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
  if [ $((now-prev)) -ge $((interval*3600)) ]; then
    if awk '/^\[list:script\]/{s=1;next} /^\[/{s=0} s && /^https:\/\/[^|]+\|[^|]*\|1([[:space:]]*)?$/{found=1} END{exit !found}' "$PG/settings.conf" 2>/dev/null; then
      sh "$MODDIR/scripts/jsruntime/sync-subs.sh" >> "$PG/jsruntime/scheduler.log" 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then printf '%s\n' "$now" > "$stamp"; else echo "[$(date '+%F %T')] refresh failed rc=$rc; retry next hour" >> "$PG/jsruntime/scheduler.log"; fi
    fi
  fi
  sleep 3600
done
