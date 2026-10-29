#!/system/bin/sh
# FX 1.0.0 VPN subscription boot updater.
# Only persist last-success timestamp after the subscription transaction succeeds.
MODDIR=${1:-${MODDIR:-}}
PG=${2:-${PG:-/data/adb/privacyguard}}
if [ -z "$MODDIR" ] || [ ! -f "$MODDIR/module.prop" ]; then
  _au_d=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
  [ -f "$_au_d/module.prop" ] && MODDIR=$_au_d
fi
[ -n "$MODDIR" ] && [ -f "$MODDIR/module.prop" ] || { echo "vpn-auto-update: module directory unresolved; skipped"; exit 0; }
CONF="$PG/settings.conf"
[ -s "$CONF" ] || exit 0
awk '/^\[/ { sections=1 } sections == 0 && $0 == "vpn_auto_update=1" { found=1 } END { exit(found ? 0 : 1) }' "$CONF" || exit 0
_interval=$(sed -n '/^\[conf:vpn\]/,/^\[/p' "$CONF" | grep -m1 '^auto_update_h=' | cut -d= -f2- | tr -d '[:space:]')
case "$_interval" in ''|*[!0-9]*) _interval=24 ;; esac
_interval=$(printf '%s' "$_interval" | sed 's/^0*//'); [ -n "$_interval" ] || _interval=0
if [ "${#_interval}" -gt 5 ]; then _interval=8760; else
  [ "$_interval" -lt 1 ] 2>/dev/null && _interval=1
  [ "$_interval" -gt 8760 ] 2>/dev/null && _interval=8760
fi
_now=$(date +%s 2>/dev/null)
case "$_now" in ''|*[!0-9]*) echo "vpn-auto-update: clock unavailable; skipped"; exit 0 ;; esac
_now=$(printf '%s' "$_now" | sed 's/^0*//'); [ -n "$_now" ] || _now=0
[ "${#_now}" -gt 11 ] && { echo "vpn-auto-update: clock out of range; skipped"; exit 0; }
_stamp="$PG/vpn-sub-last"; _prev=0
if [ -f "$_stamp" ]; then
  _prev=$(cat "$_stamp" 2>/dev/null | tr -d '[:space:]')
  case "$_prev" in ''|*[!0-9]*) _prev=0 ;; esac
  _prev=$(printf '%s' "$_prev" | sed 's/^0*//'); [ -n "$_prev" ] || _prev=0
  if [ "${#_prev}" -gt 10 ] || [ "$_prev" -gt $((_now + 86400)) ] 2>/dev/null; then _prev=0; fi
fi
[ $((_now - _prev)) -lt $((_interval * 3600)) ] && exit 0
if sh "$MODDIR/scripts/apply.sh" vpn-sub; then
  _tmp="$_stamp.tmp.$$"
  if printf '%s\n' "$_now" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$_stamp" 2>/dev/null; then
    echo "vpn-auto-update: subscription transaction succeeded; success stamp advanced"
  else rm -f "$_tmp" 2>/dev/null; echo "vpn-auto-update: succeeded but stamp commit failed; next boot may retry"; fi
else
  _rc=$?; rm -f "$_stamp.tmp.$$" 2>/dev/null
  echo "vpn-auto-update: update failed (rc=$_rc); previous success stamp preserved"
fi
exit 0
