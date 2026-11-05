#!/system/bin/sh
# Reconcile FX's transparent-proxy overlay when Android's active VPN appears,
# disappears, changes owner/interface, or transitions through an unknown handover.
# This watcher never edits firewall rules itself; apply.sh owns every transaction.
set -u
MODE=${1:-start}
case "$0" in
  */scripts/vpn-external-watchdog.sh) SELF=$0; _MODDIR=${0%/scripts/vpn-external-watchdog.sh} ;;
  *) SELF=${SELF:-$0}; _MODDIR=${MODDIR:-/data/adb/modules/privacyguard} ;;
esac
MODDIR=${2:-$_MODDIR}
PG=${3:-/data/adb/privacyguard}
SELF=$(readlink -f "$SELF" 2>/dev/null || printf '%s' "$SELF")
PIDFILE="$PG/vpn-external-watchdog.pid"
STATEFILE="$PG/vpn-external-watchdog.state"
APPLIEDFILE="$PG/vpn-external-watchdog.applied-state"
LOG="$PG/vpn-external-watchdog.log"
CORE_RETRY_FILE="$PG/vpn-core-health-retry"

_log() { printf '[%s] vpn-external-watchdog: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
_valid_pid() {
  _p=$1
  case "$_p" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_p" -gt 1 ] 2>/dev/null || return 1
  [ -r "/proc/$_p/cmdline" ] || return 1
  _cmd=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
  case "$_cmd" in *"$SELF"*' loop '*) return 0 ;; *) return 1 ;; esac
}
_write_state() {
  _path=$1; _value=$2
  _tmp="$_path.tmp.$$"
  (umask 077; printf '%s\n' "$_value" > "$_tmp") || { rm -f "$_tmp" 2>/dev/null; return 1; }
  chmod 600 "$_tmp" 2>/dev/null || :
  mv -f "$_tmp" "$_path" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
}
_managed_core_needs_reconcile() {
  # Borrow MagicNet's key invariant: process liveness is not data-plane health.
  # FX status.sh verifies the committed REDIRECT path AND its local listener.
  [ -x "$MODDIR/scripts/status.sh" ] || return 1
  [ -r "$PG/settings.conf" ] || return 1
  _mode=$(sed -n 's/^vpn_mode=//p' "$PG/settings.conf" | head -1)
  [ -n "$_mode" ] || _mode=direct
  [ "$_mode" != direct ] || return 1
  grep -q '^vpn_core=1$' "$PG/settings.conf" || return 1
  # No selected node means there is nothing to recover; avoid periodic retries
  # that would only repeat a known configuration error.
  _node=$(sed -n 's/^vpn_node=//p' "$PG/settings.conf" | head -1)
  [ -n "$_node" ] || return 1
  # Do not fight intentional fail-safe suspension when an external VPN is
  # present but overlay compatibility is disabled, or the probe is ambiguous.
  _st=$(_probe_state)
  case "$_st" in
    none) ;;
    tunnel\|*) grep -q '^vpn_external_compat=1$' "$PG/settings.conf" || return 1 ;;
    *) return 1 ;;
  esac
  _health=$(PG="$PG" CONF="$PG/settings.conf" MODDIR="$MODDIR" PG_MODDIR="$MODDIR" sh "$MODDIR/scripts/status.sh" json 2>/dev/null) || return 1
  case "$_health" in *'"vpn_on":true'*) return 1 ;; esac
  case "$_health" in *'"vpn_on":false'*) return 0 ;; *) return 1 ;; esac
}
_core_health_reconcile() {
  _managed_core_needs_reconcile || return 0
  _now=$(date +%s 2>/dev/null)
  case "$_now" in ''|*[!0-9]*) return 0 ;; esac
  _last=$(cat "$CORE_RETRY_FILE" 2>/dev/null)
  case "$_last" in ''|*[!0-9]*) _last=0 ;; esac
  [ $((_now - _last)) -ge 30 ] || return 0
  _write_state "$CORE_RETRY_FILE" "$_now" || return 0
  _log 'managed proxy health is degraded (status vpn_on=false); requesting serialized fast apply recovery'
  if PG="$PG" CONF="$PG/settings.conf" MODDIR="$MODDIR" PG_MODDIR="$MODDIR" sh "$MODDIR/scripts/apply.sh" fast >> "$LOG" 2>&1; then
    _log 'managed proxy health recovery apply completed; next probe will verify data-plane state'
  else
    _rc=$?
    _log "managed proxy health recovery failed (rc=$_rc); throttled retry remains scheduled"
  fi
}

_probe_state() {
  _json=$(PG="$PG" CONF="$PG/settings.conf" MODDIR="$MODDIR" PG_MODDIR="$MODDIR" sh "$MODDIR/scripts/external-vpn-probe.sh" 2>/dev/null) || _json=''
  _status=$(printf '%s\n' "$_json" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)
  case "$_status" in
    none) printf '%s' 'none' ;;
    tunnel)
      _if=$(printf '%s\n' "$_json" | sed -n 's/.*"interface":"\([^"]*\)".*/\1/p' | head -1)
      _uid=$(printf '%s\n' "$_json" | sed -n 's/.*"owner_uid":"\([^"]*\)".*/\1/p' | head -1)
      case "$_if" in ''|*[!A-Za-z0-9_.:-]*) printf '%s' 'unknown|invalid-interface' ; return ;; esac
      case "$_uid" in ''|*[!0-9]*|0) printf '%s' 'unknown|invalid-owner-uid' ; return ;; esac
      printf 'tunnel|%s|%s' "$_if" "$_uid"
      ;;
    unknown)
      _why=$(printf '%s\n' "$_json" | sed -n 's/.*"reason":"\([^"]*\)".*/\1/p' | head -1 | tr -cd 'A-Za-z0-9_.:-')
      printf 'unknown|%s' "${_why:-unavailable}"
      ;;
    *) printf '%s' 'unknown|invalid-probe-output' ;;
  esac
}

if [ "$MODE" = snapshot ]; then
  mkdir -p "$PG" 2>/dev/null || exit 1
  _st=$(_probe_state)
  _write_state "$STATEFILE" "$_st" || exit 1
  # The boot service calls mark-applied only after its first apply.sh succeeds.
  rm -f "$APPLIEDFILE" 2>/dev/null || :
  exit 0
fi
if [ "$MODE" = mark-applied ]; then
  [ -s "$STATEFILE" ] || { _st=$(_probe_state); _write_state "$STATEFILE" "$_st" || exit 1; }
  _st=$(cat "$STATEFILE" 2>/dev/null)
  [ -n "$_st" ] || exit 1
  _write_state "$APPLIEDFILE" "$_st"
  exit $?
fi
if [ "$MODE" = stop ]; then
  _old=$(cat "$PIDFILE" 2>/dev/null)
  if _valid_pid "$_old"; then
    kill -TERM "$_old" 2>/dev/null || :
    _n=0
    while [ "$_n" -lt 30 ] && _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; do sleep 0.2; _n=$((_n+1)); done
    if _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; then
      # Check identity again immediately before force termination; never kill a reused PID.
      _valid_pid "$_old" && kill -KILL "$_old" 2>/dev/null || :
    fi
    if _valid_pid "$_old" && kill -0 "$_old" 2>/dev/null; then
      _log "unable to stop owned watcher pid=$_old; preserving marker"
      exit 1
    fi
  fi
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" != "$_old" ] || rm -f "$PIDFILE" 2>/dev/null || :
  exit 0
fi
if [ "$MODE" = start ]; then
  mkdir -p "$PG" 2>/dev/null || exit 1
  _old=$(cat "$PIDFILE" 2>/dev/null)
  if _valid_pid "$_old"; then exit 0; fi
  rm -f "$PIDFILE" 2>/dev/null || :
  nohup sh "$SELF" loop "$MODDIR" "$PG" >> "$LOG" 2>&1 &
  _new=$!
  _tmp="$PIDFILE.tmp.$$"
  printf '%s\n' "$_new" > "$_tmp" || { kill "$_new" 2>/dev/null || :; exit 1; }
  chmod 600 "$_tmp" 2>/dev/null || :
  mv -f "$_tmp" "$PIDFILE" || { rm -f "$_tmp"; _valid_pid "$_new" && kill "$_new" 2>/dev/null || :; exit 1; }
  _n=0
  while [ "$_n" -lt 30 ]; do
    _cur=$(cat "$PIDFILE" 2>/dev/null)
    if [ "$_cur" = "$_new" ] && _valid_pid "$_new" && kill -0 "$_new" 2>/dev/null; then
      _log "started and verified watcher pid=$_new"
      exit 0
    fi
    if ! kill -0 "$_new" 2>/dev/null; then break; fi
    sleep 0.1
    _n=$((_n+1))
  done
  _log "watcher child could not prove liveness after PID publication (pid=$_new)"
  if _valid_pid "$_new"; then kill -TERM "$_new" 2>/dev/null || :; fi
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" != "$_new" ] || rm -f "$PIDFILE" 2>/dev/null || :
  exit 1
fi
[ "$MODE" = loop ] || { echo 'usage: vpn-external-watchdog.sh {snapshot|mark-applied|start|loop|stop} [module_dir] [data_dir]' >&2; exit 64; }
trap '_cur=$(cat "$PIDFILE" 2>/dev/null); [ "$_cur" = "$$" ] && rm -f "$PIDFILE"; exit 0' HUP INT TERM
_readywait=0
while [ "$_readywait" -lt 30 ]; do
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" = "$$" ] && break
  sleep 0.1
  _readywait=$((_readywait+1))
done
_cur=$(cat "$PIDFILE" 2>/dev/null)
if [ "$_cur" != "$$" ]; then _log 'PID ownership was not published in time; exiting safely'; exit 0; fi
_interval=${FX_VPN_WATCH_INTERVAL:-5}
case "$_interval" in ''|*[!0-9]*) _interval=5 ;; esac
[ "$_interval" -ge 1 ] 2>/dev/null && [ "$_interval" -le 300 ] 2>/dev/null || _interval=5
while [ -f "$MODDIR/module.prop" ]; do
  _cur=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_cur" = "$$" ] || { _log 'PID ownership changed; exiting'; exit 0; }
  _now=$(_probe_state)
  _core_health_reconcile
  _old=$(cat "$STATEFILE" 2>/dev/null)
  if [ "$_now" != "$_old" ]; then
    _log "external VPN state changed: ${_old:-unset} -> $_now"
    _write_state "$STATEFILE" "$_now" || _log 'unable to persist observed state; will retry'
  fi
  _applied=$(cat "$APPLIEDFILE" 2>/dev/null)
  if [ "$_now" != "$_applied" ]; then
    case "$_now" in
      unknown\|*)
        # A handover/ambiguous probe is not a stable state. Applying it can
        # repeatedly rebuild firewall rules while Android switches VPN owners.
        # Keep the last committed marker and retry once the probe is authoritative.
        _log "external VPN state is ambiguous ($_now); deferring apply until a stable probe"
        sleep "$_interval"
        continue
        ;;
    esac
    _log "reconciling current external VPN state via apply.sh fast (state=$_now)"
    if PG="$PG" CONF="$PG/settings.conf" MODDIR="$MODDIR" PG_MODDIR="$MODDIR" sh "$MODDIR/scripts/apply.sh" fast >> "$LOG" 2>&1; then
      _after=$(_probe_state)
      if [ "$_after" = "$_now" ]; then
        _write_state "$STATEFILE" "$_now" || :
        _write_state "$APPLIEDFILE" "$_now" || _log 'apply succeeded but state commit failed; will retry'
        _log "state reconciled successfully: $_now"
      else
        _log "VPN changed during apply ($_now -> $_after); leaving applied marker unchanged for retry"
      fi
    else
      _rc=$?
      _log "apply.sh fast failed (rc=$_rc); retaining unapplied marker for retry"
    fi
  fi
  sleep "$_interval"
done
_log 'module.prop vanished; stopping watcher'
_cur=$(cat "$PIDFILE" 2>/dev/null)
[ "$_cur" = "$$" ] && rm -f "$PIDFILE" 2>/dev/null || :
exit 0
