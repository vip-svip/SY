#!/system/bin/sh
# Yulong Tasker/widget compatibility controller; only updates FX's canonical VPN route.
set -eu
umask 077
[ "$#" -eq 3 ] || { echo "usage: $0 MODULE_DIR STATE_DIR {status|start|stop|toggle}" >&2; exit 64; }
MP=$1
PG=$2
CMD=$3
[ "$MP" = "-" ] && MP=""
[ "$PG" = "-" ] && PG=/data/adb/privacyguard
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard \
      /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then MP=$d; break; fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] && [ -s "$MP/scripts/util.sh" ] \
  || { echo "FX module missing" >&2; exit 20; }
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "FX state directory missing or unsafe" >&2; exit 21; }
[ -f "$PG/settings.conf" ] && [ ! -L "$PG/settings.conf" ] \
  || { echo "FX settings.conf missing or unsafe" >&2; exit 21; }
# Child scripts are separate shells; explicitly pass the resolved module/state paths.
export MP PG
. "$MP/scripts/util.sh"

LOCK="$PG/yulong-vpn-control.lock"
LOG="$PG/yulong-vpn-control.log"
LOCK_HELD=0
status_json() { sh "$MP/scripts/status.sh"; }
is_running() { printf '%s' "$1" | grep -Eq '"vpn_on"[[:space:]]*:[[:space:]]*true'; }
mode_from_status() { printf '%s' "$1" | sed -n 's/.*"vpn_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'; }
lock_acquire() {
  n=0
  while [ "$n" -lt 40 ]; do
    if [ ! -L "$LOCK" ] && mkdir "$LOCK" 2>/dev/null; then
      LOCK_HELD=1
      if printf '%s\n' "$$" > "$LOCK/owner.tmp.$$" &&
          chmod 600 "$LOCK/owner.tmp.$$" &&
          mv -f "$LOCK/owner.tmp.$$" "$LOCK/owner"; then return 0; fi
      rm -f "$LOCK/owner.tmp.$$" "$LOCK/owner" 2>/dev/null || :
      rmdir "$LOCK" 2>/dev/null || :
      LOCK_HELD=0
      return 1
    fi
    [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || return 1
    owner=$(cat "$LOCK/owner" 2>/dev/null || true)
    case "$owner" in ''|*[!0-9]*) owner= ;; esac
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      sleep 0.25
    elif [ "$n" -lt 4 ]; then
      sleep 0.25
    else
      stale="$LOCK.stale.$$.$n"
      if [ ! -e "$stale" ] && [ ! -L "$stale" ] && mv "$LOCK" "$stale" 2>/dev/null; then
        moved=$(cat "$stale/owner" 2>/dev/null || true)
        if [ -z "$moved" ] || { [ "$moved" = "$owner" ] && ! kill -0 "$moved" 2>/dev/null; }; then
          rm -f "$stale/owner" 2>/dev/null || :
          rmdir "$stale" 2>/dev/null || :
        elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
          mv "$stale" "$LOCK" 2>/dev/null || :
        fi
      fi
      sleep 0.25
    fi
    n=$((n+1))
  done
  echo "VPN control is busy; no change was applied" >&2
  return 75
}
lock_release() {
  [ "$LOCK_HELD" = 1 ] || return 0
  if [ ! -L "$LOCK" ] && [ -d "$LOCK" ] && [ ! -L "$LOCK/owner" ] &&
      [ "$(cat "$LOCK/owner" 2>/dev/null || true)" = "$$" ]; then
    release="$LOCK.release.$$"
    if [ ! -e "$release" ] && [ ! -L "$release" ] && mv "$LOCK" "$release" 2>/dev/null; then
      if [ "$(cat "$release/owner" 2>/dev/null || true)" = "$$" ]; then
        rm -f "$release/owner" 2>/dev/null || :
        rmdir "$release" 2>/dev/null || :
      elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
        mv "$release" "$LOCK" 2>/dev/null || :
      fi
    fi
  fi
  LOCK_HELD=0
}
trap lock_release EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

apply_mode() {
  target=$1
  if [ "$target" = "direct" ]; then
    sh "$MP/scripts/apply.sh" fast >> "$LOG" 2>&1
  else
    sh "$MP/scripts/apply.sh" >> "$LOG" 2>&1
  fi
}
restore_mode() {
  prior=$1
  pg_set vpn_mode "$prior" >/dev/null 2>&1 || return 1
  apply_mode "$prior"
}
start_vpn() {
  lock_acquire || return $?
  old_mode=$(pg_get vpn_mode direct 2>/dev/null || echo direct)
  state=$(status_json 2>/dev/null || true)
  if is_running "$state"; then echo "vpn_already_running=1"; return 0; fi
  node=$(pg_get vpn_node "" 2>/dev/null || true)
  [ -n "$node" ] || { echo "VPN_NO_NODE_SELECTED: select a VPN node before starting" >&2; return 32; }
  case "$old_mode" in
    direct) target=global ;;
    global|rule|tun) target=$old_mode ;;
    *) echo "invalid saved VPN mode; no change was applied" >&2; return 22 ;;
  esac
  pg_set vpn_mode "$target" || return 31
  if ! apply_mode "$target"; then
    restore_mode "$old_mode" >/dev/null 2>&1 || echo "VPN rollback apply failed" >> "$LOG"
    echo "VPN_START_APPLY_FAILED: previous route mode restored" >&2
    return 1
  fi
  state=$(status_json 2>/dev/null || true)
  actual_mode=$(mode_from_status "$state")
  if [ "$actual_mode" != "$target" ] || ! is_running "$state"; then
    restore_mode "$old_mode" >/dev/null 2>&1 || echo "VPN rollback apply failed" >> "$LOG"
    echo "VPN_START_NOT_CONFIRMED: status.sh did not confirm the selected route" >&2
    return 33
  fi
  echo "vpn_started=1"
  echo "vpn_mode=$target"
}
stop_vpn() {
  lock_acquire || return $?
  old_mode=$(pg_get vpn_mode direct 2>/dev/null || echo direct)
  state=$(status_json 2>/dev/null || true)
  if [ "$old_mode" = "direct" ] && ! is_running "$state"; then
    echo "vpn_already_stopped=1"
    return 0
  fi
  pg_set vpn_mode direct || return 31
  if ! apply_mode direct; then
    restore_mode "$old_mode" >/dev/null 2>&1 || echo "VPN rollback apply failed" >> "$LOG"
    echo "VPN_STOP_APPLY_FAILED: previous route mode restored" >&2
    return 1
  fi
  state=$(status_json 2>/dev/null || true)
  actual_mode=$(mode_from_status "$state")
  if [ "$actual_mode" != "direct" ] || is_running "$state"; then
    restore_mode "$old_mode" >/dev/null 2>&1 || echo "VPN rollback apply failed" >> "$LOG"
    echo "VPN_STOP_NOT_CONFIRMED: status.sh did not confirm direct mode" >&2
    return 34
  fi
  echo "vpn_stopped=1"
}
case "$CMD" in
  status) status_json ;;
  start) start_vpn ;;
  stop) stop_vpn ;;
  toggle)
    state=$(status_json 2>/dev/null || true)
    if is_running "$state"; then stop_vpn; else start_vpn; fi
    ;;
  *) echo "usage: $0 MODULE_DIR STATE_DIR {status|start|stop|toggle}" >&2; exit 64 ;;
esac
