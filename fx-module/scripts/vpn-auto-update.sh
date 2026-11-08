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
# The boot updater runs as root. Never read settings or write timestamps
# through a symlinked state path (including an intermediate parent).
_au_safe_absolute_path() {
  _au_path=$1
  case "$_au_path" in /*) : ;; *) return 1 ;; esac
  case "$_au_path" in *//*|*/|*'/../'*|*/..|*'/./'*|*/.) return 1 ;; esac
  _au_walk=
  _au_rest=${_au_path#/}
  while [ -n "$_au_rest" ]; do
    case "$_au_rest" in
      */*) _au_part=${_au_rest%%/*}; _au_rest=${_au_rest#*/} ;;
      *) _au_part=$_au_rest; _au_rest= ;;
    esac
    [ -n "$_au_part" ] || return 1
    _au_walk="$_au_walk/$_au_part"
    [ ! -L "$_au_walk" ] || return 1
  done
  return 0
}
_au_safe_absolute_path "$PG" && [ -d "$PG" ] && [ ! -L "$PG" ] || {
  echo "vpn-auto-update: unsafe state directory; skipped" >&2
  exit 0
}
CONF="$PG/settings.conf"
[ -f "$CONF" ] && [ ! -L "$CONF" ] && [ -s "$CONF" ] || exit 0
awk '/^\[/ { sections=1 } sections == 0 && $0 == "vpn_auto_update=1" { found=1 } END { exit(found ? 0 : 1) }' "$CONF" || exit 0
_interval=$(sed -n '/^\[conf:vpn\]/,/^\[/p' "$CONF" | grep -m1 '^auto_update_h=' | cut -d= -f2- | tr -d '[:space:]')
case "$_interval" in ''|*[!0-9]*) _interval=24 ;; esac
_interval=$(printf '%s' "$_interval" | sed 's/^0*//'); [ -n "$_interval" ] || _interval=0
# Strip leading zeros before shell arithmetic and bound length before numeric comparisons.
if [ "${#_interval}" -gt 5 ]; then _interval=8760; else
  [ "$_interval" -lt 1 ] 2>/dev/null && _interval=1
  [ "$_interval" -gt 8760 ] 2>/dev/null && _interval=8760
fi
_now=$(date +%s 2>/dev/null)
case "$_now" in ''|*[!0-9]*) echo "vpn-auto-update: clock unavailable; skipped without changing success stamp"; exit 0 ;; esac
_now=$(printf '%s' "$_now" | sed 's/^0*//'); [ -n "$_now" ] || _now=0
[ "${#_now}" -gt 11 ] && { echo "vpn-auto-update: clock value out of range; skipped without changing success stamp"; exit 0; }
_stamp="$PG/vpn-sub-last"; _prev=0
if [ -L "$_stamp" ] || { [ -e "$_stamp" ] && [ ! -f "$_stamp" ]; }; then
  echo "vpn-auto-update: unsafe success timestamp path; skipped" >&2
  exit 0
fi
if [ -f "$_stamp" ]; then
  _prev=$(cat "$_stamp" 2>/dev/null | tr -d '[:space:]')
  case "$_prev" in ''|*[!0-9]*) _prev=0 ;; esac
  _prev=$(printf '%s' "$_prev" | sed 's/^0*//'); [ -n "$_prev" ] || _prev=0
  if [ "${#_prev}" -gt 10 ] || [ "$_prev" -gt $((_now + 86400)) ] 2>/dev/null; then
    echo "vpn-auto-update: invalid future/overflow stamp; treating as never successfully updated"
    _prev=0
  fi
fi
[ $((_now - _prev)) -lt $((_interval * 3600)) ] && exit 0
if sh "$MODDIR/scripts/apply.sh" vpn-sub; then
  _tmp=$(mktemp "$PG/.vpn-sub-last.XXXXXX" 2>/dev/null) || _tmp=
  if [ -n "$_tmp" ] && printf '%s\n' "$_now" > "$_tmp" 2>/dev/null \
      && chmod 600 "$_tmp" 2>/dev/null && mv -f "$_tmp" "$_stamp" 2>/dev/null; then
    echo "vpn-auto-update: subscription transaction succeeded; success stamp advanced to $_now"
  else
    [ -z "$_tmp" ] || rm -f "$_tmp" 2>/dev/null
    # Success without a durable stamp is safe: next boot may refresh again.
    echo "vpn-auto-update: subscription succeeded but success stamp could not be committed; next boot may retry"
  fi
else
  _rc=$?
  rm -f "$_stamp.tmp.$" 2>/dev/null
  # Do not advance the stamp on error. The last successful timestamp remains intact.
  echo "vpn-auto-update: subscription update failed (rc=$_rc); previous success stamp preserved for retry"
fi
exit 0
