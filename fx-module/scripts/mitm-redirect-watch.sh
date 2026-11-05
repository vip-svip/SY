#!/system/bin/sh
# Safety watcher started only after explicit MITM redirect enable. If a known
# external VPN appears (or listener health degrades), remove FX-owned rules and
# stop the MITM listener. No third-party firewall chain is edited.
MODDIR=${1:-${PG_MODDIR:-${MODDIR:-}}}
[ -n "$MODDIR" ] && [ -f "$MODDIR/module.prop" ] || exit 2
PG=/data/adb/privacyguard
PIDFILE="$PG/mitm/redirect-watch.pid"
REDIRECT="$MODDIR/scripts/mitm-redirect.sh"
ENGINE="$MODDIR/scripts/mitm-engine.sh"
LOG="$PG/mitm/redirect-watch.log"
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG"; }
cleanup() {
  _pid=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_pid" = "$$" ] && rm -f "$PIDFILE"
}
trap cleanup EXIT HUP INT TERM
while [ -f "$MODDIR/module.prop" ]; do
  _status=$(sh "$REDIRECT" status 2>/dev/null)
  case "$_status" in
    *'"ipv4_redirect":"disabled"'*)
      # Brief grace period avoids racing a rapid disable/re-enable action.
      sleep 3
      _status2=$(sh "$REDIRECT" status 2>/dev/null)
      case "$_status2" in *'"ipv4_redirect":"disabled"'*) exit 0 ;; esac
      ;;
    *'"ipv4_redirect":"enabled"'*)
      _vpn_if=$(sh "$REDIRECT" external-vpn 2>/dev/null)
      _vpn_rc=$?
      _bad_listener=0
      case "$_status" in *'"health":"degraded"'*) _bad_listener=1 ;; esac
      if [ -n "$_vpn_if" ] && [ "$_vpn_rc" -eq 0 ]; then
        log "external tunnel detected ($_vpn_if); disabling FX-owned MITM redirect to protect the outer VPN"
      elif [ "$_vpn_rc" -eq 2 ]; then
        log 'external VPN state cannot be inspected; disabling FX-owned MITM redirect fail-safe'
      elif [ "$_bad_listener" = 1 ]; then
        log 'MITM listener health is degraded; disabling FX-owned redirect fail-safe'
      else
        sleep 5
        continue
      fi
      if sh "$REDIRECT" disable >>"$LOG" 2>&1; then
        log 'MITM redirect and listener safely disabled by watcher'
        exit 0
      fi
      log 'MITM auto-disable failed; retaining watcher to retry owned-chain cleanup'
      ;;
    *'"ipv4_redirect":"partial"'*|*'"ipv4_redirect":"orphaned-chain"'*)
      log 'partial/orphaned owned chain detected; attempting safe disable'
      if sh "$REDIRECT" disable >>"$LOG" 2>&1; then exit 0; fi
      ;;
    *)
      # Unknown state is not permission to edit firewall rules. Keep observing.
      sleep 5
      continue
      ;;
  esac
  sleep 5
done
exit 0
