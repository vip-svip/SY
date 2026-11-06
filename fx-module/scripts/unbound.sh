#!/system/bin/sh
# FX-owned local recursive DNS resolver: root/TLD/authoritative recursion + on-device cache.
# This is not a forwarder to Tencent/Alibaba/Cloudflare; it queries authoritative DNS directly.
set -u
case "$0" in
  */scripts/unbound.sh) MODDIR=${0%/scripts/unbound.sh} ;;
  *) MODDIR=${MODDIR:-/data/adb/modules/privacyguard} ;;
esac
ACTION=${1:-status}
[ "$#" -ge 2 ] && MODDIR=$2
PG=${3:-/data/adb/privacyguard}
ROOT="$MODDIR/engines/unbound"
BIN="$ROOT/unbound"
CHECKBIN="$ROOT/unbound-checkconf"
ANCHOR="$ROOT/unbound-anchor"
PROBE="$ROOT/fx-dns-probe"
ROOT_HINTS="$ROOT/root.hints"
ROOT_KEY_SEED="$ROOT/root.key.seed"
STATE="$PG/unbound"
LIFECYCLE_LOCK="$STATE/lifecycle.lock"
CFG="$STATE/unbound.conf"
WORK="$STATE/work"
PIDFILE="$STATE/managed.pid"
EGRESS="$PG/unbound-vpn-egress-ip"
LOG="$STATE/engine.log"
PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:/usr/bin:/bin
export PATH

_path_components_are_safe() {
  _safe_path=$1
  case "$_safe_path" in /*) : ;; *) return 1 ;; esac
  case "$_safe_path" in *//*|*/../*|*/..|*/./*|*/.) return 1 ;; esac
  _safe_rest=${_safe_path#/}
  _safe_walk=
  while [ -n "$_safe_rest" ]; do
    case "$_safe_rest" in
      */*) _safe_part=${_safe_rest%%/*}; _safe_rest=${_safe_rest#*/} ;;
      *) _safe_part=$_safe_rest; _safe_rest= ;;
    esac
    case "$_safe_part" in ''|.|..) return 1 ;; esac
    _safe_walk="$_safe_walk/$_safe_part"
    [ ! -L "$_safe_walk" ] || return 1
  done
  return 0
}
_safe_file_or_absent() {
  _safe_file=$1
  _path_components_are_safe "$_safe_file" || return 1
  [ ! -L "$_safe_file" ] || return 1
  [ ! -e "$_safe_file" ] || [ -f "$_safe_file" ]
}
_new_private_temp() {
  _temp_template=$1
  _temp_path=$(umask 077; mktemp "$_temp_template") || return 1
  [ -f "$_temp_path" ] && [ ! -L "$_temp_path" ] || return 1
  chmod 600 "$_temp_path" 2>/dev/null || { rm -f "$_temp_path"; return 1; }
  printf '%s\n' "$_temp_path"
}
_prepare_state_dirs() {
  _path_components_are_safe "$PG" || { echo "unsafe Unbound parent state path" >&2; return 1; }
  [ -d "$PG" ] && [ ! -L "$PG" ] || { echo "Unbound parent state directory is missing or unsafe" >&2; return 1; }
  _path_components_are_safe "$STATE" && _path_components_are_safe "$WORK" || {
    echo "unsafe Unbound state path" >&2; return 1;
  }
  if [ -e "$STATE" ]; then
    [ -d "$STATE" ] && [ ! -L "$STATE" ] || { echo "Unbound state path is not a real directory" >&2; return 1; }
  else
    (umask 077; mkdir "$STATE") || return 1
  fi
  if [ -e "$WORK" ]; then
    [ -d "$WORK" ] && [ ! -L "$WORK" ] || { echo "Unbound work path is not a real directory" >&2; return 1; }
  else
    (umask 077; mkdir "$WORK") || return 1
  fi
  chmod 700 "$STATE" "$WORK" 2>/dev/null || {
    echo "cannot enforce private Unbound state/work directory permissions" >&2
    return 1
  }
  for _safe_candidate in "$CFG" "$PIDFILE" "$LOG" "$STATE/root.key" "$EGRESS"; do
    _safe_file_or_absent "$_safe_candidate" || {
      echo "Unbound refuses a symlink or non-regular state file: $_safe_candidate" >&2
      return 1
    }
  done
  return 0
}
_log() {
  _path_components_are_safe "$STATE" || return 0
  [ -d "$STATE" ] && [ ! -L "$STATE" ] && _safe_file_or_absent "$LOG" || return 0
  printf '[%s] unbound: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :
}
_is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
_hash() {
  _file=$1
  _sidecar="$2"
  _safe_file_or_absent "$_file" && [ -f "$_file" ] && [ -s "$_file" ] || {
    _log "runtime input is missing, linked or not a regular file: $_file"; return 1;
  }
  _safe_file_or_absent "$_sidecar" && [ -f "$_sidecar" ] && [ -s "$_sidecar" ] || {
    _log "runtime checksum sidecar is missing, linked or not a regular file: $_sidecar"; return 1;
  }
  _expected=$(awk 'NF && length($1)==64 && $1 ~ /^[a-fA-F0-9]+$/ {print tolower($1); exit}' "$_sidecar" 2>/dev/null)
  [ "${#_expected}" -eq 64 ] || { _log "invalid SHA-256 sidecar: $_sidecar"; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    _actual=$(sha256sum "$_file" 2>/dev/null | awk '{print tolower($1)}')
  elif command -v toybox >/dev/null 2>&1; then
    _actual=$(toybox sha256sum "$_file" 2>/dev/null | awk '{print tolower($1)}')
  else
    _log 'SHA-256 command unavailable; refusing recursive DNS startup'; return 1
  fi
  [ "$_actual" = "$_expected" ] || { _log "SHA-256 mismatch: $_file"; return 1; }
  return 0
}
_check_files() {
  [ -x "$BIN" ] && [ -x "$CHECKBIN" ] && [ -x "$ANCHOR" ] && [ -x "$PROBE" ] || { _log 'unbound runtime/checker/anchor/probe missing or not executable'; return 1; }
  _hash "$BIN" "$ROOT/unbound.sha256" || return 1
  _hash "$CHECKBIN" "$ROOT/unbound-checkconf.sha256" || return 1
  _hash "$ANCHOR" "$ROOT/unbound-anchor.sha256" || return 1
  _hash "$PROBE" "$ROOT/fx-dns-probe.sha256" || return 1
  _hash "$ROOT_HINTS" "$ROOT/root.hints.sha256" || return 1
  _hash "$ROOT_KEY_SEED" "$ROOT/root.key.seed.sha256" || return 1
  grep -q 'A.ROOT-SERVERS.NET.*198.41.0.4' "$ROOT_HINTS" || { _log 'root hints A-root entry missing'; return 1; }
  grep -q 'M.ROOT-SERVERS.NET.*202.12.27.33' "$ROOT_HINTS" || { _log 'root hints M-root entry missing'; return 1; }
  grep -Eq '^\.[[:space:]]+IN[[:space:]]+DNSKEY[[:space:]]+257[[:space:]]+3[[:space:]]+8[[:space:]]' "$ROOT_KEY_SEED" || { _log 'root trust-anchor seed malformed'; return 1; }
  return 0
}
# Avoid deleting a replacement resolver's PID marker when an older start/stop
# operation finishes after another lifecycle operation has published a new PID.
_remove_pid_marker_if_matches() {
  _expected=$1
  [ -n "$_expected" ] || return 0
  _safe_file_or_absent "$PIDFILE" || return 1
  [ -f "$PIDFILE" ] || return 0
  _current=$(cat "$PIDFILE" 2>/dev/null) || return 1
  [ "$_current" = "$_expected" ] || return 0
  # Atomically isolate the marker before deleting it. A concurrent start may
  # publish a replacement PID after the rename; the old stop must never unlink
  # that new marker merely because it read the old contents moments earlier.
  _release="$PIDFILE.release.$$"
  _n=0
  while { [ -e "$_release" ] || [ -L "$_release" ]; } && [ "$_n" -lt 20 ]; do
    _n=$((_n + 1))
    _release="$PIDFILE.release.$$.$_n"
  done
  [ ! -e "$_release" ] && [ ! -L "$_release" ] || return 1
  mv "$PIDFILE" "$_release" 2>/dev/null || return 1
  _moved=$(cat "$_release" 2>/dev/null || true)
  if [ "$_moved" = "$_expected" ] && [ ! -L "$_release" ] && [ -f "$_release" ]; then
    rm -f "$_release" 2>/dev/null || return 1
    return 0
  fi
  if [ ! -e "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
    mv "$_release" "$PIDFILE" 2>/dev/null || :
  fi
  return 1
}
_owned_pid() {
  _safe_file_or_absent "$PIDFILE" && [ -f "$PIDFILE" ] || return 1
  _p=$(cat "$PIDFILE" 2>/dev/null)
  _is_uint "$_p" || return 1
  [ "$_p" -gt 1 ] 2>/dev/null || return 1
  [ -r "/proc/$_p/cmdline" ] || return 1
  # Keep argv boundaries intact: substring matching a flattened cmdline can
  # mistake an unrelated process argument for the managed resolver executable.
  _argv=$(tr '\000' '\n' < "/proc/$_p/cmdline" 2>/dev/null) || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$BIN" || return 1
  printf '%s\n' "$_argv" | grep -Fqx -- "$CFG" || return 1
  printf '%s\n' "$_p"

}
_vpn_egress_config() {
  # Root Proxy currently proves an IPv4 source/route only. Disable IPv6
  # upstream sockets in this mode so recursive AAAA lookups cannot escape
  # over an unrelated system IPv6 default route. DNS AAAA records remain
  # available because the resolver can return them over IPv4 transport.
  _safe_file_or_absent "$EGRESS" || {
    _log "unsafe VPN egress marker; refusing an unbound config without a proven route"
    return 1
  }
  [ -f "$EGRESS" ] || return 0
  _vpn_ip=$(tr -d '\r\n' < "$EGRESS" 2>/dev/null) || return 1
  [ -n "$_vpn_ip" ] || { _log "empty VPN egress marker"; return 1; }
  printf '%s\n' "$_vpn_ip" | awk -F. '
    NF != 4 {ok=0; exit}
    {
      ok=1
      for (i=1; i<=4; i++) {
        if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255 ||
            ($i != "0" && $i ~ /^0/)) ok=0
      }
      first=$1+0; second=$2+0
      if (first==0 || first==127 || first>=224 ||
          (first==169 && second==254)) ok=0
    }
    END {exit(ok ? 0 : 1)}
  ' || { _log "invalid VPN egress marker; refusing unbound startup"; return 1; }
  printf '  do-ip6: no\n  outgoing-interface: %s\n' "$_vpn_ip"
}
_unbound_runtime_value() {
  printf '%s\n' "$_unbound_runtime_output" | awk -F= -v wanted="$1" '
    $1==wanted {count++; value=$2}
    END {if(count!=1)exit 1; print value}
  '
}
_render_config() {
  _egress_config=$(_vpn_egress_config) || return 1
  _unbound_control="$MODDIR/scripts/yulong-ad-control.sh"
  [ -f "$_unbound_control" ] && [ ! -L "$_unbound_control" ] || {
    _log 'DNS control adapter is missing or unsafe; refusing Unbound config render'
    return 1
  }
  _unbound_runtime_output=$(MP="$MODDIR" PG="$PG" sh "$_unbound_control" unbound-runtime-get 2>/dev/null) || {
    _log 'unable to read Unbound runtime settings'
    return 1
  }
  [ "$(printf '%s\n' "$_unbound_runtime_output" | sed -n '1p')" = FXYULONGUNBOUND1 ] || {
    _log 'Unbound runtime settings response header is invalid'
    return 1
  }
  _ub_cache_max_ttl=$(_unbound_runtime_value UNBOUND_CACHE_MAX_TTL) || return 1
  _ub_cache_min_ttl=$(_unbound_runtime_value UNBOUND_CACHE_MIN_TTL) || return 1
  _ub_serve_expired=$(_unbound_runtime_value UNBOUND_SERVE_EXPIRED) || return 1
  _ub_serve_expired_ttl=$(_unbound_runtime_value UNBOUND_SERVE_EXPIRED_TTL) || return 1
  _ub_serve_expired_reply_ttl=$(_unbound_runtime_value UNBOUND_SERVE_EXPIRED_REPLY_TTL) || return 1
  _ub_serve_expired_client_timeout=$(_unbound_runtime_value UNBOUND_SERVE_EXPIRED_CLIENT_TIMEOUT) || return 1
  _ub_prefetch=$(_unbound_runtime_value UNBOUND_PREFETCH) || return 1
  _ub_qname_minimisation=$(_unbound_runtime_value UNBOUND_QNAME_MINIMISATION) || return 1
  case "$_ub_serve_expired:$_ub_prefetch:$_ub_qname_minimisation" in
    0:0:0|0:0:1|0:1:0|0:1:1|1:0:0|1:0:1|1:1:0|1:1:1) : ;;
    *) _log 'Unbound runtime boolean setting is invalid'; return 1 ;;
  esac
  case "$_ub_serve_expired" in 1) _ub_serve_expired_yaml=yes ;; 0) _ub_serve_expired_yaml=no ;; esac
  case "$_ub_prefetch" in 1) _ub_prefetch_yaml=yes ;; 0) _ub_prefetch_yaml=no ;; esac
  case "$_ub_qname_minimisation" in 1) _ub_qname_minimisation_yaml=yes ;; 0) _ub_qname_minimisation_yaml=no ;; esac
  cat <<EOF_CFG
server:
  username: ""
  chroot: ""
  directory: "$WORK"
  pidfile: "$STATE/unbound.pid"
  logfile: "$LOG"
  use-syslog: no
  verbosity: 1
  num-threads: 1
  interface: 127.0.0.1
$_egress_config  port: 5353
  access-control: 127.0.0.0/8 allow
  do-ip4: yes
  do-udp: yes
  do-tcp: yes
  root-hints: "$ROOT_HINTS"
  auto-trust-anchor-file: "$STATE/root.key"
  module-config: "validator iterator"
  qname-minimisation: $_ub_qname_minimisation_yaml
  harden-glue: yes
  harden-dnssec-stripped: yes
  hide-identity: yes
  hide-version: yes
  aggressive-nsec: yes
  prefetch: $_ub_prefetch_yaml
  prefetch-key: yes
  serve-expired: $_ub_serve_expired_yaml
  serve-expired-ttl: $_ub_serve_expired_ttl
  serve-expired-reply-ttl: $_ub_serve_expired_reply_ttl
  serve-expired-client-timeout: $_ub_serve_expired_client_timeout
  edns-buffer-size: 1232
  max-udp-size: 1232
  msg-cache-size: 8m
  rrset-cache-size: 16m
  key-cache-size: 4m
  neg-cache-size: 2m
  cache-max-ttl: $_ub_cache_max_ttl
  cache-min-ttl: $_ub_cache_min_ttl
  unwanted-reply-threshold: 10000000
EOF_CFG
}
_maybe_refresh_anchor() {
  [ -x "$ANCHOR" ] || return 0
  [ -s "$STATE/root.key" ] || return 0
  # Unbound auto-updates RFC5011 anchors while online. If the device was offline
  # for more than two weeks, make one bounded startup refresh attempt after the
  # old process is stopped; network failure is non-fatal because the bundled
  # DNSKEY seed remains valid and the resolver's health probe decides activation.
  _old_anchor=$(find "$STATE/root.key" -mtime +14 -print -quit 2>/dev/null)
  [ -n "$_old_anchor" ] || return 0
  # unbound-anchor is a one-shot helper and does not consume Unbound's
  # outgoing-interface setting. Running it while Root Proxy has pinned the
  # resolver to a third-party VPN could therefore leak the refresh request
  # over the device's ordinary default route. Defer refresh to Unbound's own
  # RFC5011 maintenance after its VPN-bound listener is online.
  if [ -f "$EGRESS" ]; then
    _log 'deferring one-shot trust-anchor refresh: VPN-bound Unbound will maintain RFC5011 state'
    return 0
  fi
  if command -v timeout >/dev/null 2>&1; then
    _tmp_anchor=$(_new_private_temp "$STATE/root.key.before-refresh.XXXXXX") || return 0
    cp "$STATE/root.key" "$_tmp_anchor" 2>/dev/null || { rm -f "$_tmp_anchor"; return 0; }
    _refresh_rc=0
    timeout 5 "$ANCHOR" -a "$STATE/root.key" >> "$LOG" 2>&1 || _refresh_rc=$?
    if [ "$_refresh_rc" -ne 0 ]; then
      # A failed/timed-out helper may leave a syntactically plausible but
      # incomplete replacement. Never promote its output merely because a
      # single DNSKEY line survived; restore the exact pre-refresh file.
      if ! mv -f "$_tmp_anchor" "$STATE/root.key" 2>/dev/null; then
        _log 'trust-anchor refresh failed and previous anchor rollback failed; preserving recovery copy'
        return 1
      fi
      _log 'bounded trust-anchor refresh failed; previous anchor restored'
      return 0
    fi
    _log 'stale root trust anchor refresh helper completed'
    if ! grep -Eq '^\\.[[:space:]]+IN[[:space:]]+DNSKEY[[:space:]]+257[[:space:]]+3[[:space:]]+8[[:space:]]' "$STATE/root.key" 2>/dev/null; then
      # Never continue with an invalid refreshed anchor if rollback itself
      # fails. Keep the private pre-refresh copy for recovery and abort startup.
      if ! mv -f "$_tmp_anchor" "$STATE/root.key" 2>/dev/null; then
        _log 'invalid root trust-anchor refresh and rollback failed; preserving previous anchor copy'
        return 1
      fi
      _log 'root trust anchor refresh output failed validation; previous file restored'
      return 0
    fi
    rm -f "$_tmp_anchor" 2>/dev/null || return 1
  else
    _log 'timeout helper unavailable; skipping offline trust-anchor refresh to avoid unbounded boot delay'
  fi
  return 0
}
_probe() {
  "$PROBE" 127.0.0.1 5353 5 >> "$LOG" 2>&1
}
_stop() {
  _safe_file_or_absent "$PIDFILE" || { _log 'refusing to stop through an unsafe PID marker'; return 1; }
  _p=$(_owned_pid 2>/dev/null) || _p=''
  if [ -z "$_p" ]; then
    _stale=$(cat "$PIDFILE" 2>/dev/null)
    _remove_pid_marker_if_matches "$_stale"
    return 0
  fi
  # Revalidate ownership immediately before signalling: the PID may have
  # exited and been reused after the first /proc/cmdline check.
  _same=$(_owned_pid 2>/dev/null) || _same=''
  if [ "$_same" != "$_p" ]; then
    _log "refusing to signal PID $_p because process ownership changed before TERM"
    return 1
  fi
  kill -TERM "$_p" 2>/dev/null || :
  _i=0
  while [ "$_i" -lt 20 ] && kill -0 "$_p" 2>/dev/null; do
    _same=$(_owned_pid 2>/dev/null) || _same=''
    [ "$_same" = "$_p" ] || break
    sleep 0.25; _i=$((_i+1))
  done
  _same=$(_owned_pid 2>/dev/null) || _same=''
  if [ "$_same" = "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    _same=$(_owned_pid 2>/dev/null) || _same=''
    if [ "$_same" = "$_p" ]; then
      kill -KILL "$_p" 2>/dev/null || :
    fi
  fi
  _i=0
  while [ "$_i" -lt 10 ] && kill -0 "$_p" 2>/dev/null; do sleep 0.2; _i=$((_i+1)); done
  _same=$(_owned_pid 2>/dev/null) || _same=''
  if [ "$_same" = "$_p" ] && kill -0 "$_p" 2>/dev/null; then _log 'stop timed out; preserving PID marker'; return 1; fi
  _remove_pid_marker_if_matches "$_p"
  _log 'stopped managed recursive resolver'
  return 0
}
_ensure() {
  _prepare_state_dirs || { _log 'refusing startup because private state paths are unsafe'; return 1; }
  _check_files || { _stop || :; return 1; }
  if [ ! -s "$STATE/root.key" ] || ! grep -Eq '^\.[[:space:]]+IN[[:space:]]+DNSKEY[[:space:]]+257[[:space:]]+3[[:space:]]+8[[:space:]]' "$STATE/root.key" 2>/dev/null; then
    _tmp_key=$(_new_private_temp "$STATE/root.key.tmp.XXXXXX") || return 1
    cp "$ROOT_KEY_SEED" "$_tmp_key" || { rm -f "$_tmp_key"; return 1; }
    mv -f "$_tmp_key" "$STATE/root.key" || { rm -f "$_tmp_key"; return 1; }
  fi
  _tmp=$(_new_private_temp "$STATE/unbound.conf.tmp.XXXXXX") || return 1
  _render_config > "$_tmp" || { rm -f "$_tmp"; return 1; }
  if ! "$CHECKBIN" "$_tmp" >> "$LOG" 2>&1; then
    _log 'generated recursive resolver config rejected by pinned unbound-checkconf'; rm -f "$_tmp"; return 1
  fi
  _p=$(_owned_pid 2>/dev/null) || _p=''
  if [ -n "$_p" ] && [ -s "$CFG" ] && cmp -s "$_tmp" "$CFG"; then
    rm -f "$_tmp"
    if _probe; then return 0; fi
    _log 'existing resolver failed unique uncached query; restarting'
    _stop || return 1
  elif [ -n "$_p" ]; then
    _stop || { rm -f "$_tmp"; return 1; }
  fi
  if ! _maybe_refresh_anchor; then
    _log 'trust-anchor refresh rollback was not confirmed; refusing resolver startup'
    rm -f "$_tmp"
    return 1
  fi
  mv -f "$_tmp" "$CFG" || { rm -f "$_tmp"; return 1; }
  # The config was created with _new_private_temp (umask 077 + chmod 600)
  # and retains that mode across the atomic rename.
  nohup "$BIN" -d -c "$CFG" >/dev/null 2>&1 &
  _new=$!
  _pid_tmp=$(_new_private_temp "$STATE/managed.pid.tmp.XXXXXX") || { kill "$_new" 2>/dev/null || :; return 1; }
  printf '%s\n' "$_new" > "$_pid_tmp" || { rm -f "$_pid_tmp"; kill "$_new" 2>/dev/null || :; return 1; }
  mv -f "$_pid_tmp" "$PIDFILE" || { rm -f "$_pid_tmp"; kill "$_new" 2>/dev/null || :; return 1; }
  _i=0; _same=''
  while [ "$_i" -lt 20 ]; do
    _same=$(_owned_pid 2>/dev/null) || _same=''
    [ "$_same" = "$_new" ] && break
    if ! kill -0 "$_new" 2>/dev/null; then _log 'process exited during recursive DNS startup'; _remove_pid_marker_if_matches "$_new"; return 1; fi
    _i=$((_i+1)); sleep 1
  done
  if [ "$_same" = "$_new" ] && _probe; then
    _log 'ready; uncached root-recursive DNS query succeeded'
    return 0
  fi
  _log 'startup or uncached recursive-DNS health probe failed; resolver stopped and forwarding path remains untouched'
  _stop || :
  return 1
}


_release_lifecycle_lock() {
  [ -d "$LIFECYCLE_LOCK" ] && [ ! -L "$LIFECYCLE_LOCK" ] || return 0
  _lock_owner_file="$LIFECYCLE_LOCK/owner"
  [ -f "$_lock_owner_file" ] && [ ! -L "$_lock_owner_file" ] || return 0
  _lock_owner=$(cat "$_lock_owner_file" 2>/dev/null) || return 0
  [ "$_lock_owner" = "$$" ] || return 0
  rm -f "$_lock_owner_file" 2>/dev/null || return 1
  rmdir "$LIFECYCLE_LOCK" 2>/dev/null || return 1
  return 0
}
_with_lifecycle_lock() {
  _locked_action=$1
  _prepare_state_dirs || return 1
  _wait=0
  while ! mkdir "$LIFECYCLE_LOCK" 2>/dev/null; do
    [ ! -L "$LIFECYCLE_LOCK" ] && [ -d "$LIFECYCLE_LOCK" ] || {
      _log 'unsafe Unbound lifecycle lock path'
      return 1
    }
    if [ "$_wait" -ge 35 ]; then
      _log 'Unbound lifecycle operation is busy; refusing concurrent start/stop'
      return 1
    fi
    sleep 1
    _wait=$((_wait+1))
  done
  if ! printf '%s\n' "$$" > "$LIFECYCLE_LOCK/owner"; then
    rmdir "$LIFECYCLE_LOCK" 2>/dev/null || :
    _log 'unable to publish Unbound lifecycle lock owner'
    return 1
  fi
  chmod 700 "$LIFECYCLE_LOCK" 2>/dev/null || {
    rm -f "$LIFECYCLE_LOCK/owner" 2>/dev/null || :
    rmdir "$LIFECYCLE_LOCK" 2>/dev/null || :
    return 1
  }
  trap '_release_lifecycle_lock' EXIT
  trap 'exit 1' HUP INT TERM
  "$_locked_action"
}

case "$ACTION" in
  render-config) _render_config ;;
  ensure) _with_lifecycle_lock _ensure ;;
  stop) _with_lifecycle_lock _stop ;;
  status)
    if _p=$(_owned_pid 2>/dev/null); then
      if _probe; then echo ready; exit 0; fi
      echo running-unhealthy; exit 1
    fi
    echo stopped; exit 1
    ;;
  *) echo 'usage: unbound.sh {render-config|ensure|stop|status} [module_dir] [data_dir]' >&2; exit 64 ;;
esac
