#!/system/bin/sh
# FX local DNS recovery watchdog. It only reconciles FX-owned Unbound/AdGuard
# processes and never changes VPN apps, Android Private DNS, or third-party routes.
set -u
umask 077
ACTION=${1:-status}
MODDIR=${2:-/data/adb/modules/privacyguard}
PG=${3:-/data/adb/privacyguard}
SCRIPT="$MODDIR/scripts/localdns-watchdog.sh"
PIDFILE="$PG/localdns-watchdog.pid"
LOG="$PG/localdns-watchdog.log"
PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:/usr/bin:/bin
export PATH

_path_safe() {
  _path=$1
  case "$_path" in /*) : ;; *) return 1 ;; esac
  case "$_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _rest=${_path#/}
  _walk=
  while [ -n "$_rest" ]; do
    case "$_rest" in
      */*) _part=${_rest%%/*}; _rest=${_rest#*/} ;;
      *) _part=$_rest; _rest= ;;
    esac
    case "$_part" in ''|.|..) return 1 ;; esac
    _walk="$_walk/$_part"
    [ ! -L "$_walk" ] || return 1
  done
  return 0
}
_file_safe_or_absent() {
  _file=$1
  _path_safe "$_file" || return 1
  [ ! -L "$_file" ] || return 1
  [ ! -e "$_file" ] || [ -f "$_file" ]
}
_prepare() {
  _path_safe "$MODDIR" && [ -d "$MODDIR" ] || {
    echo "unsafe FX module path" >&2; return 1;
  }
  _path_safe "$PG" && [ -d "$PG" ] || {
    echo "unsafe FX state path" >&2; return 1;
  }
  [ -f "$SCRIPT" ] && [ ! -L "$SCRIPT" ] || {
    echo "local DNS watchdog script is missing or unsafe" >&2; return 1;
  }
  _file_safe_or_absent "$PIDFILE" && _file_safe_or_absent "$LOG" || {
    echo "local DNS watchdog PID/log path is unsafe" >&2; return 1;
  }
}
_log() {
  _file_safe_or_absent "$LOG" || return 0
  printf '[%s] localdns-watchdog: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :
}
_read_pid() {
  _file_safe_or_absent "$PIDFILE" && [ -f "$PIDFILE" ] || return 1
  _pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
  case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_pid" -gt 1 ] 2>/dev/null || return 1
  printf '%s\n' "$_pid"
}
_owned_pid() {
  _pid=$1
  case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_pid" -gt 1 ] 2>/dev/null || return 1
  [ -r "/proc/$_pid/cmdline" ] || return 1
  _argv=$(tr '\000' '\n' < "/proc/$_pid/cmdline" 2>/dev/null) || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$SCRIPT" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "watch" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$MODDIR" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$PG" || return 1
  printf '%s\n' "$_pid"
}
_release_pid_if_matches() {
  _expected=$1
  _file_safe_or_absent "$PIDFILE" || return 1
  [ -f "$PIDFILE" ] || return 0
  _current=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ "$_current" = "$_expected" ] || return 0
  _release="$PIDFILE.release.$$"
  [ ! -e "$_release" ] && [ ! -L "$_release" ] || return 1
  mv "$PIDFILE" "$_release" 2>/dev/null || return 1
  _moved=$(cat "$_release" 2>/dev/null || :)
  if [ "$_moved" = "$_expected" ] && [ ! -L "$_release" ] && [ -f "$_release" ]; then
    rm -f "$_release" 2>/dev/null || return 1
    return 0
  fi
  if [ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    mv "$_release" "$PIDFILE" 2>/dev/null || :
  fi
  return 1
}
_value() {
  printf '%s\n' "$1" | awk -F'|' -v key="$2" '
    $1==key {count++; value=$2}
    END {if(count==1) print value; else exit 1}
  '
}
_reconcile_once() {
  _status=$(MP="$MODDIR" PG="$PG" sh "$MODDIR/scripts/native-dns-settings.sh" status 2>/dev/null) || {
    _issue="native DNS status unavailable"
    return 1
  }
  [ "$(printf '%s\n' "$_status" | sed -n '1p')" = FXDNS1 ] || {
    _issue="native DNS status response invalid"
    return 1
  }
  _agh=$(_value "$_status" dns_engine_adguardhome) || {
    _issue="AdGuard Home setting unreadable"
    return 1
  }
  _forward=$(_value "$_status" dns_forward) || {
    _issue="Unbound setting unreadable"
    return 1
  }
  case "$_agh:$_forward" in
    0:0) _issue=; return 0 ;;
    0:1|1:1) : ;;
    1:0)
      _issue="AdGuard Home is enabled while Unbound forwarding is disabled"
      return 1
      ;;
    *) _issue="DNS engine flags are invalid"; return 1 ;;
  esac

  _upstream_state=$(_value "$_status" dns_upstream_state 2>/dev/null || printf unknown)
  _fallback_mode=$(_value "$_status" dns_fallback_mode 2>/dev/null || printf unknown)

  _unbound_status=$(sh "$MODDIR/scripts/unbound.sh" status "$MODDIR" "$PG" 2>/dev/null || :)
  if [ "$_unbound_status" != ready ]; then
    _log_once "Unbound state is $_unbound_status; attempting owned-service reconciliation"
    if ! sh "$MODDIR/scripts/unbound.sh" ensure "$MODDIR" "$PG" >> "$LOG" 2>&1; then
      _issue="Unbound recovery failed"
      return 1
    fi
    _unbound_status=$(sh "$MODDIR/scripts/unbound.sh" status "$MODDIR" "$PG" 2>/dev/null || :)
    [ "$_unbound_status" = ready ] || {
      _issue="Unbound remains $_unbound_status after recovery"
      return 1
    }
    _log "Unbound recovery completed"
  fi

  if [ "$_agh" = 1 ]; then
    case "$_upstream_state" in
      ready) : ;;
      *)
        _issue="AdGuard recovery deferred because upstream state is $_upstream_state"
        return 1
        ;;
    esac
    case "$_fallback_mode" in
      unknown)
        _issue="AdGuard recovery deferred because fallback DNS configuration is unknown"
        return 1
        ;;
    esac
    _agh_status=$(sh "$MODDIR/scripts/adguardhome.sh" status "$MODDIR" "$PG" 2>/dev/null || :)
    if [ "$_agh_status" != ready ]; then
      _log_once "AdGuard Home state is $_agh_status; attempting owned-service reconciliation"
      if ! sh "$MODDIR/scripts/adguardhome.sh" ensure "$MODDIR" "$PG" >> "$LOG" 2>&1; then
        _issue="AdGuard Home recovery failed"
        return 1
      fi
      _agh_status=$(sh "$MODDIR/scripts/adguardhome.sh" status "$MODDIR" "$PG" 2>/dev/null || :)
      [ "$_agh_status" = ready ] || {
        _issue="AdGuard Home remains $_agh_status after recovery"
        return 1
      }
      _log "AdGuard Home recovery completed"
    fi
  fi
  _issue=
  return 0
}
_log_once() {
  _message=$1
  if [ "${_last_issue:-}" != "$_message" ]; then
    _log "$_message"
    _last_issue=$_message
  fi
}
_watch_cleanup() {
  _release_pid_if_matches "$$" || :
}
_watch() {
  _prepare || exit 1
  trap '_watch_cleanup' EXIT
  trap 'exit 0' HUP INT TERM
  _last_issue=
  _log "watch loop started"
  while :; do
    if _reconcile_once; then
      if [ -n "$_last_issue" ]; then
        _log "DNS services returned to configured ready state"
        _last_issue=
      fi
    else
      _log_once "${_issue:-DNS recovery attempt failed}"
    fi
    sleep 30
  done
}
_start() {
  _prepare || return 1
  if [ -e "$PIDFILE" ]; then
    _old=$(_read_pid) || {
      echo "local DNS watchdog PID record is malformed; refusing to replace it" >&2
      return 22
    }
    if _owned_pid "$_old" >/dev/null 2>&1; then
      echo "running pid=$_old"
      return 0
    fi
    if kill -0 "$_old" 2>/dev/null; then
      echo "local DNS watchdog PID $_old is live but process identity cannot be confirmed" >&2
      return 23
    fi
    _release_pid_if_matches "$_old" || {
      echo "unable to clear stale local DNS watchdog PID record" >&2
      return 1
    }
    _log "cleared stale watchdog PID record for exited PID $_old"
  fi
  nohup sh "$SCRIPT" watch "$MODDIR" "$PG" >/dev/null 2>&1 &
  _new=$!
  _tmp=$(umask 077; mktemp "$PG/localdns-watchdog.pid.tmp.XXXXXX") || {
    kill -TERM "$_new" 2>/dev/null || :
    return 1
  }
  if ! printf '%s\n' "$_new" > "$_tmp" || ! chmod 600 "$_tmp" ||
     ! mv -f "$_tmp" "$PIDFILE"; then
    rm -f "$_tmp" 2>/dev/null || :
    kill -TERM "$_new" 2>/dev/null || :
    return 1
  fi
  _tries=0
  while [ "$_tries" -lt 10 ]; do
    if _owned_pid "$_new" >/dev/null 2>&1; then
      echo "started pid=$_new"
      return 0
    fi
    if ! kill -0 "$_new" 2>/dev/null; then break; fi
    sleep 0.2
    _tries=$((_tries+1))
  done
  _release_pid_if_matches "$_new" || :
  echo "local DNS watchdog did not establish a verifiable process identity" >&2
  return 1
}
_stop() {
  _prepare || return 1
  [ -e "$PIDFILE" ] || { echo stopped; return 0; }
  _pid=$(_read_pid) || {
    echo "local DNS watchdog PID record is malformed or unsafe" >&2
    return 22
  }
  if ! _owned_pid "$_pid" >/dev/null 2>&1; then
    if kill -0 "$_pid" 2>/dev/null; then
      echo "local DNS watchdog PID $_pid is live but process identity cannot be confirmed" >&2
      return 23
    fi
    _release_pid_if_matches "$_pid" || return 1
    echo "stopped stale-pid=$_pid"
    return 0
  fi
  kill -TERM "$_pid" 2>/dev/null || :
  _tries=0
  while [ "$_tries" -lt 50 ] && kill -0 "$_pid" 2>/dev/null; do
    _same=$(_owned_pid "$_pid" 2>/dev/null || :)
    [ "$_same" = "$_pid" ] || break
    sleep 0.2
    _tries=$((_tries+1))
  done
  _same=$(_owned_pid "$_pid" 2>/dev/null || :)
  if [ "$_same" = "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
    _same=$(_owned_pid "$_pid" 2>/dev/null || :)
    [ "$_same" = "$_pid" ] || {
      echo "local DNS watchdog process identity changed during stop" >&2
      return 23
    }
    kill -KILL "$_pid" 2>/dev/null || :
  fi
  _tries=0
  while [ "$_tries" -lt 20 ] && kill -0 "$_pid" 2>/dev/null; do
    sleep 0.2
    _tries=$((_tries+1))
  done
  _same=$(_owned_pid "$_pid" 2>/dev/null || :)
  if [ "$_same" = "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
    echo "local DNS watchdog did not stop; preserving PID record" >&2
    return 1
  fi
  _release_pid_if_matches "$_pid" || return 1
  echo "stopped pid=$_pid"
}
case "$ACTION" in
  start) [ "$#" -eq 3 ] || exit 2; _start ;;
  stop) [ "$#" -eq 3 ] || exit 2; _stop ;;
  status)
    [ "$#" -eq 3 ] || exit 2
    _prepare || exit 1
    if _pid=$(_read_pid 2>/dev/null) && _owned_pid "$_pid" >/dev/null 2>&1; then
      echo "running pid=$_pid"
      exit 0
    fi
    echo stopped
    exit 1
    ;;
  watch) [ "$#" -eq 3 ] || exit 2; _watch ;;
  *) echo "usage: localdns-watchdog.sh {start|stop|status} MODULE_DIR STATE_DIR" >&2; exit 64 ;;
esac
