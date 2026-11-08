#!/system/bin/sh
# Module-owned PackageManager watcher for Root Proxy DNS whitelist reconciliation.
# Calls the existing atomic package-event handler only when package/UID state changes.
set -u
CMD=${1:-status}
MP=${2:-${MP:-}}
PG=${3:-${PG:-/data/adb/privacyguard}}
case "$0" in */scripts/yulong-root-proxy-package-watch.sh) SCRIPT=$0 ;; *) SCRIPT=${SCRIPT:-} ;; esac
if [ -z "$MP" ]; then
  for _candidate in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard; do
    if [ -f "$_candidate/module.prop" ] && grep -q '^id=privacyguard$' "$_candidate/module.prop" 2>/dev/null; then
      MP=$_candidate
      break
    fi
  done
fi
[ -n "$MP" ] && path_components_safe "$MP" && [ -d "$MP" ] && [ ! -L "$MP" ] \
  && [ -f "$MP/module.prop" ] && [ ! -L "$MP/module.prop" ] \
  || { echo "FX module directory unavailable or unsafe" >&2; exit 20; }
[ -n "$SCRIPT" ] || SCRIPT="$MP/scripts/yulong-root-proxy-package-watch.sh"
path_components_safe "$SCRIPT" && [ -f "$SCRIPT" ] && [ ! -L "$SCRIPT" ] \
  || { echo "Root Proxy package watcher script is missing or unsafe" >&2; exit 20; }
ROOT_PROXY="$MP/scripts/yulong-root-proxy.sh"
path_components_safe "$ROOT_PROXY" && [ -f "$ROOT_PROXY" ] && [ ! -L "$ROOT_PROXY" ] \
  || { echo "Root Proxy helper is missing or unsafe" >&2; exit 20; }
path_components_safe "$PG" && [ -d "$PG" ] && [ ! -L "$PG" ] \
  || { echo "FX state directory is missing or unsafe" >&2; exit 21; }

PIDFILE="$PG/yulong-root-proxy-package-watch.pid"
SNAPSHOT="$PG/yulong-root-proxy-package-watch.snapshot"
LOCK="$PG/yulong-root-proxy-package-watch.lock"
LOG="$PG/yulong-root-proxy-package-watch.log"
INTERVAL=${FX_ROOT_PROXY_PACKAGE_WATCH_INTERVAL:-30}
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=30 ;; esac
[ "$INTERVAL" -ge 10 ] || INTERVAL=10
[ "$INTERVAL" -le 300 ] || INTERVAL=300
umask 077

path_components_safe() {
  _candidate=$1
  case "$_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_candidate" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _rest=${_candidate#/}
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
reject_unsafe_path() {
  _path=$1
  path_components_safe "$_path" || return 1
  [ ! -L "$_path" ] || return 1
  [ ! -e "$_path" ] || [ -f "$_path" ] || [ -d "$_path" ]
}
for _path in "$PIDFILE" "$SNAPSHOT" "$LOG"; do
  reject_unsafe_path "$_path" || { echo "unsafe Root Proxy package watcher state path: $_path" >&2; exit 21; }
  [ ! -e "$_path" ] || [ -f "$_path" ] || { echo "Root Proxy package watcher state file is not regular: $_path" >&2; exit 21; }
done
reject_unsafe_path "$LOCK" || { echo "unsafe Root Proxy package watcher lock path" >&2; exit 21; }
[ ! -e "$LOCK" ] || [ -d "$LOCK" ] || { echo "Root Proxy package watcher lock path is not a directory" >&2; exit 21; }

log() {
  printf '[%s] root-proxy-package-watch: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :
}
process_matches() {
  _pid=$1
  case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$_pid" 2>/dev/null || return 1
  [ -r "/proc/$_pid/cmdline" ] || return 1
  _args=$(tr '\000' '\n' < "/proc/$_pid/cmdline" 2>/dev/null) || return 1
  _a2=$(printf '%s\n' "$_args" | sed -n '2p')
  _a3=$(printf '%s\n' "$_args" | sed -n '3p')
  _a4=$(printf '%s\n' "$_args" | sed -n '4p')
  _a5=$(printf '%s\n' "$_args" | sed -n '5p')
  [ "$_a2" = "$SCRIPT" ] && [ "$_a3" = "watch-loop" ] \
    && [ "$_a4" = "$MP" ] && [ "$_a5" = "$PG" ]
}
acquire_lock() {
  _tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || return 1
    _owner=$(cat "$LOCK/pid" 2>/dev/null || true)
    case "$_owner" in
      ''|*[!0-9]*)
        if [ "$_tries" -ge 20 ]; then
          _stale="$LOCK.stale.$$"
          if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] && mv "$LOCK" "$_stale" 2>/dev/null; then
            rm -f "$_stale/pid" 2>/dev/null || :
            rmdir "$_stale" 2>/dev/null || :
          fi
        fi
        ;;
      *)
        if ! kill -0 "$_owner" 2>/dev/null; then
          _stale="$LOCK.stale.$$"
          if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] && mv "$LOCK" "$_stale" 2>/dev/null; then
            rm -f "$_stale/pid" 2>/dev/null || :
            rmdir "$_stale" 2>/dev/null || :
          fi
        fi
        ;;
    esac
    [ "$_tries" -lt 50 ] || return 1
    _tries=$((_tries+1))
    sleep 0.1
  done
  printf '%s\n' "$$" > "$LOCK/pid" || { rmdir "$LOCK" 2>/dev/null || :; return 1; }
  chmod 600 "$LOCK/pid" 2>/dev/null || { rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || :; return 1; }
  return 0
}
release_lock() {
  [ ! -L "$LOCK" ] && [ -d "$LOCK" ] || return 0
  [ "$(cat "$LOCK/pid" 2>/dev/null || true)" = "$$" ] || return 0
  rm -f "$LOCK/pid" 2>/dev/null || :
  rmdir "$LOCK" 2>/dev/null || :
}
write_snapshot() {
  _hash=$1
  [ ! -L "$SNAPSHOT" ] || return 1
  _tmp=$(mktemp "$SNAPSHOT.tmp.XXXXXX") || return 1
  if printf 'FXYRP-PACKAGES1\n%s\n' "$_hash" > "$_tmp" \
      && chmod 600 "$_tmp" && [ -f "$_tmp" ] && [ ! -L "$_tmp" ] \
      && mv -f "$_tmp" "$SNAPSHOT"; then
    return 0
  fi
  rm -f "$_tmp"
  return 1
}
package_snapshot_hash() {
  _raw=$(cmd package list packages -U 2>/dev/null) || return 1
  [ -n "$_raw" ] || return 1
  # A partial PackageManager listing must never become the new baseline:
  # otherwise a malformed row could hide a package/UID change and leave
  # Root Proxy applying stale per-UID exclusions.
  _rows=$(printf '%s\n' "$_raw" | awk '
    BEGIN {valid=1; count=0}
    {
      if($0 ~ /^[ \t]*$/) next
      line=$0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      n=split(line, field, /[ \t]+/)
      if(n!=2 || field[1] !~ /^package:[A-Za-z0-9_.-]+$/ ||
          field[2] !~ /^uid:[0-9]+$/) {valid=0; next}
      pkg=substr(field[1],9); uid=substr(field[2],5)
      if(pkg !~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ ||
          uid !~ /^[0-9]+$/ || uid=="0" || pkg in seen) {valid=0; next}
      seen[pkg]=1
      rows[++count]=pkg "|" uid
    }
    END {
      if(!valid || count==0) exit 2
      for(i=1;i<=count;i++) print rows[i]
    }
  ' | LC_ALL=C sort) || return 1
  [ -n "$_rows" ] || return 1
  _hashline=$(printf '%s\n' "$_rows" | cksum 2>/dev/null) || return 1
  _hash=${_hashline%% *}
  _rest=${_hashline#* }
  _bytes=${_rest%% *}
  case "$_hash:$_bytes" in ''|*[!0-9:]*) return 1 ;; esac
  printf '%s:%s\n' "$_hash" "$_bytes"
}
run_package_event() {
  MP="$MP" PG="$PG" CONF="$PG/settings.conf" sh "$ROOT_PROXY" package-event
}
run_route_reconcile() {
  MP="$MP" PG="$PG" CONF="$PG/settings.conf" sh "$ROOT_PROXY" reconcile-route
}
current_snapshot() {
  [ ! -L "$SNAPSHOT" ] && [ -f "$SNAPSHOT" ] || return 1
  [ "$(sed -n '1p' "$SNAPSHOT" 2>/dev/null)" = "FXYRP-PACKAGES1" ] || return 1
  _value=$(sed -n '2p' "$SNAPSHOT" 2>/dev/null)
  case "$_value" in ''|*[!0-9:]*) return 1 ;; esac
  printf '%s\n' "$_value"
}
watch_loop() {
  [ ! -L "$PIDFILE" ] && [ ! -e "$PIDFILE" ] || exit 1
  _tmp=$(mktemp "$PIDFILE.tmp.XXXXXX") || exit 1
  if ! printf '%s\n' "$$" > "$_tmp" || ! chmod 600 "$_tmp" || ! mv -f "$_tmp" "$PIDFILE"; then
    rm -f "$_tmp"
    exit 1
  fi
  cleanup_loop() {
    if [ ! -L "$PIDFILE" ] && [ -f "$PIDFILE" ] \
        && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ]; then rm -f "$PIDFILE" 2>/dev/null || :; fi
  }
  trap cleanup_loop EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  # Reconcile package/UID policy once at boot. The periodic loop below also
  # revalidates the active VPN route/egress even when package inventory is unchanged.
  if run_package_event >> "$LOG" 2>&1; then
    _new=$(package_snapshot_hash 2>/dev/null || true)
    [ -z "$_new" ] || write_snapshot "$_new" || log "unable to persist initial PackageManager snapshot"
  else
    log "initial package-event reconciliation failed; will retry"
  fi
  while [ -f "$MP/module.prop" ] && [ -d "$PG" ] && [ ! -L "$PG" ]; do
    sleep "$INTERVAL"
    _new=$(package_snapshot_hash 2>/dev/null || true)
    if [ -z "$_new" ]; then
      log "PackageManager snapshot unavailable; retaining last-known package snapshot"
    else
      _known=$(current_snapshot 2>/dev/null || true)
      if [ "$_new" != "$_known" ]; then
        if run_package_event >> "$LOG" 2>&1; then
          write_snapshot "$_new" || log "package set reconciled but new snapshot marker could not be committed"
          log "installed package/UID set changed; Root Proxy whitelist and routes reconciled"
        else
          log "package-event reconciliation failed; retrying on next package snapshot interval"
        fi
      fi
    fi
    if ! run_route_reconcile >> "$LOG" 2>&1; then
      log "periodic VPN DNS route/egress reconciliation failed; owned redirects fail open or remain retryable"
    fi
  done
}
start_watcher() {
  acquire_lock || { echo "Root Proxy package watcher lifecycle is busy" >&2; return 75; }
  if [ -e "$PIDFILE" ]; then
    [ ! -L "$PIDFILE" ] && [ -f "$PIDFILE" ] || { release_lock; return 21; }
    _pid=$(cat "$PIDFILE" 2>/dev/null || true)
    case "$_pid" in ''|*[!0-9]*) _pid= ;; esac
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
      if process_matches "$_pid"; then
        release_lock
        echo "watcher=running pid=$_pid"
        return 0
      fi
      release_lock
      echo "Root Proxy package watcher PID belongs to another process; refusing takeover" >&2
      return 10
    fi
    rm -f "$PIDFILE"
  fi
  nohup sh "$SCRIPT" watch-loop "$MP" "$PG" </dev/null >> "$LOG" 2>&1 &
  _child=$!
  _ready=0
  _wait=0
  while [ "$_wait" -lt 50 ]; do
    if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] \
        && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$_child" ] \
        && process_matches "$_child"; then
      _ready=1
      break
    fi
    kill -0 "$_child" 2>/dev/null || break
    sleep 0.1
    _wait=$((_wait+1))
  done
  release_lock
  [ "$_ready" = 1 ] || { echo "Root Proxy package watcher did not publish a verifiable owner" >&2; return 1; }
  echo "watcher=started pid=$_child interval=$INTERVAL"
}
stop_watcher() {
  acquire_lock || { echo "Root Proxy package watcher lifecycle is busy" >&2; return 75; }
  if [ ! -e "$PIDFILE" ]; then release_lock; echo "watcher=stopped"; return 0; fi
  [ ! -L "$PIDFILE" ] && [ -f "$PIDFILE" ] || { release_lock; return 21; }
  _pid=$(cat "$PIDFILE" 2>/dev/null || true)
  case "$_pid" in ''|*[!0-9]*) release_lock; return 21 ;; esac
  if kill -0 "$_pid" 2>/dev/null; then
    process_matches "$_pid" || { release_lock; echo "watcher PID belongs to another process" >&2; return 10; }
    kill -TERM "$_pid" 2>/dev/null || :
    _wait=0
    while [ "$_wait" -lt 50 ] && kill -0 "$_pid" 2>/dev/null; do
      process_matches "$_pid" || break
      sleep 0.1
      _wait=$((_wait+1))
    done
    if kill -0 "$_pid" 2>/dev/null && process_matches "$_pid"; then
      kill -KILL "$_pid" 2>/dev/null || :
    fi
    if kill -0 "$_pid" 2>/dev/null && process_matches "$_pid"; then
      release_lock
      echo "watcher shutdown not confirmed" >&2
      return 1
    fi
  fi
  if [ ! -L "$PIDFILE" ] && [ -f "$PIDFILE" ] \
      && [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$_pid" ]; then rm -f "$PIDFILE"; fi
  release_lock
  echo "watcher=stopped"
}
case "$CMD" in
  start) start_watcher ;;
  stop|uninstall) stop_watcher ;;
  status)
    _pid=$(cat "$PIDFILE" 2>/dev/null || true)
    if process_matches "$_pid"; then echo "watcher=running pid=$_pid interval=$INTERVAL"
    else echo "watcher=stopped"; fi
    ;;
  watch-loop) watch_loop ;;
  *) echo "usage: yulong-root-proxy-package-watch.sh {start|stop|uninstall|status}" >&2; exit 64 ;;
esac
