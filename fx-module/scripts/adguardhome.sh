#!/system/bin/sh
# FX-owned AdGuard Home lifecycle. It fronts the local Unbound recursive resolver.
# DNS interception is opt-in and fails open.
set -u
case "$0" in
  */scripts/adguardhome.sh) MODDIR=${0%/scripts/adguardhome.sh} ;;
  *) MODDIR=${MODDIR:-/data/adb/modules/privacyguard} ;;
esac
ACTION=${1:-status}
[ "$#" -ge 2 ] && MODDIR=$2
PG=${3:-/data/adb/privacyguard}
BIN="$MODDIR/engines/adguardhome/AdGuardHome-android-arm64"
HASHFILE="$MODDIR/engines/adguardhome/AdGuardHome-android-arm64.sha256"
STATE="$PG/adguardhome"
CFG="$STATE/AdGuardHome.yaml"
WORK="$STATE/work"
PIDFILE="$STATE/managed.pid"
LOG="$STATE/engine.log"
AGH_PASSWORD_HASH='$2a$12$2.x1ZQ78RvLwzP0MzwMUPuVOW5e2BHAsdmf8.Z1jaqNc2ZmPDR1z2'
PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:/usr/bin:/bin
export PATH

_pg_log() {
  mkdir -p "$STATE" 2>/dev/null || :
  printf '[%s] adguardhome: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :
}
_pg_is_uint() { case "${1:-}" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
# Remove a PID marker only if it still names the process whose lifecycle
# operation is being completed. This narrows replacement races and avoids an
# old startup/stop path deleting a newer engine's marker.
_pg_remove_pid_marker_if_matches() {
  _expected=$1
  [ -n "$_expected" ] || return 0
  _current=$(cat "$PIDFILE" 2>/dev/null)
  [ "$_current" = "$_expected" ] || return 0
  rm -f "$PIDFILE" 2>/dev/null || :
}
_pg_owned_pid() {
  _p=$(cat "$PIDFILE" 2>/dev/null)
  _pg_is_uint "$_p" || return 1
  [ "$_p" -gt 1 ] 2>/dev/null || return 1
  [ -r "/proc/$_p/cmdline" ] || return 1
  _cmd=$(tr '\000' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
  case "$_cmd" in
    *"$BIN"*"$CFG"*) printf '%s\n' "$_p"; return 0 ;;
    *) return 1 ;;
  esac
}
_pg_check_binary() {
  [ -x "$BIN" ] || { _pg_log 'Android ARM64 binary missing or not executable'; return 1; }
  [ -s "$HASHFILE" ] || { _pg_log 'binary SHA-256 manifest missing'; return 1; }
  _expected=$(awk 'NF && length($1)==64 && $1 ~ /^[a-fA-F0-9]+$/ {print tolower($1); exit}' "$HASHFILE" 2>/dev/null)
  [ "${#_expected}" -eq 64 ] || { _pg_log 'binary SHA-256 manifest invalid'; return 1; }
  if command -v sha256sum >/dev/null 2>&1; then
    _actual=$(sha256sum "$BIN" 2>/dev/null | awk '{print tolower($1)}')
  elif command -v toybox >/dev/null 2>&1; then
    _actual=$(toybox sha256sum "$BIN" 2>/dev/null | awk '{print tolower($1)}')
  else
    _pg_log 'SHA-256 command unavailable; refusing DNS engine start'; return 1
  fi
  [ "$_actual" = "$_expected" ] || { _pg_log "binary SHA-256 mismatch: expected=$_expected actual=${_actual:-none}"; return 1; }
  return 0
}
_pg_render_config() {
  _rules_file="$MODDIR/fxrules/anti_fraud_96110.txt"
  [ -s "$_rules_file" ] || { _pg_log 'anti-fraud rules file missing'; return 1; }
  # Only convert domain rules explicitly marked REJECT in the FX anti-fraud set.
  # Never pull adblock/open-screen/watermark lists into this engine.
  _rules=$(awk -F, '
    /^[[:space:]]*#/ || NF < 3 { next }
    $1 !~ /^DOMAIN(-SUFFIX)?$/ || $3 != "REJECT" { next }
    {
      d=tolower($2)
      if (d !~ /^[a-z0-9.-]+$/ || d ~ /\.\./ || d ~ /^\./ || d ~ /\.$/ || d ~ /(^|\.)-/ || d ~ /-(\.|$)/) next
      print "  - \"||" d "^\""
    }
  ' "$_rules_file" | awk '!seen[$0]++')
  [ -n "$_rules" ] || { _pg_log 'no safe anti-fraud domain rules to load'; return 1; }
  cat <<EOF_CFG
http:
  address: 127.0.0.1:0
  session_ttl: 3h
  pprof:
    enabled: false
    port: 6060
  doh:
    routes:
    - GET /dns-query
    - POST /dns-query
    - GET /dns-query/{ClientID}
    - POST /dns-query/{ClientID}
    insecure_enabled: false
users:
- name: fx-local
  password: "$AGH_PASSWORD_HASH"
dns:
  bind_hosts:
  - 127.0.0.1
  - ::1
  port: 53
  # AdGuard Home is the local filter/cache front end. All cache misses go to
  # FX's loopback-only Unbound recursive resolver; no public forwarding DNS is
  # hard-coded here. Unbound queries root/TLD/authoritative servers directly.
  upstream_dns:
  - 127.0.0.1:5353
  cache_enabled: true
  cache_size: 4194304
  hostsfile_enabled: false
filtering:
  protection_enabled: true
  filtering_enabled: true
  blocked_response_ttl: 10
  safe_fs_patterns: []
  rewrites: []
  safe_search:
    enabled: false
  blocked_services:
    schedule:
      time_zone: Local
    ids: []
filters: []
user_rules:
$_rules
querylog:
  enabled: false
  file_enabled: false
  interval: 30d
  size_memory: 1000
  ignored: []
  ignored_enabled: false
statistics:
  enabled: false
  interval: 10d
  ignored: []
  ignored_enabled: false
schema_version: 34
tls:
  enabled: false
EOF_CFG
}
_pg_timeout_lookup() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 nslookup example.com 127.0.0.1 2>&1
    return $?
  elif command -v toybox >/dev/null 2>&1 && toybox timeout 3 true >/dev/null 2>&1; then
    toybox timeout 3 nslookup example.com 127.0.0.1 2>&1
    return $?
  fi
  _pg_log 'bounded timeout unavailable; DNS health probe refused'
  return 125
}
_pg_dns_probe() {
  command -v nslookup >/dev/null 2>&1 || { _pg_log 'nslookup unavailable; refusing to redirect DNS'; return 1; }
  _i=0
  while [ "$_i" -lt 3 ]; do
    _out=$(_pg_timeout_lookup); _rc=$?
    if [ "$_rc" -eq 0 ] && ! printf '%s\n' "$_out" | grep -Eiq 'NXDOMAIN|SERVFAIL|REFUSED|timed out|time out|no servers could be reached|can.t find|cannot find|connection refused|network is unreachable|temporary failure in name resolution'; then
      # Require an address in the answer section after the requested name,
      # not merely the resolver's own 127.0.0.1 address in the header.
      if printf '%s\n' "$_out" | awk '
        tolower($0) ~ /^name:[[:space:]]*example[.]com([.]|[[:space:]]|$)/ {answer=1; next}
        answer && /([0-9]{1,3}[.]){3}[0-9]{1,3}/ {found=1}
        END {exit !found}
      '; then
        return 0
      fi
    fi
    _i=$((_i+1))
    [ "$_i" -lt 3 ] && sleep 1
  done
  _pg_log "DNS health probe failed (rc=${_rc:-unknown}); last output: $(printf '%s' "${_out:-}" | tr '\n' ' ' | cut -c1-240)"
  return 1
}
_pg_stop() {
  _p=$(_pg_owned_pid 2>/dev/null) || _p=''
  if [ -z "$_p" ]; then
    # Never signal an unverified process; clean only the marker we observed.
    _stale=$(cat "$PIDFILE" 2>/dev/null)
    _pg_remove_pid_marker_if_matches "$_stale"
    return 0
  fi
  kill -TERM "$_p" 2>/dev/null || :
  _i=0
  while [ "$_i" -lt 20 ] && kill -0 "$_p" 2>/dev/null; do
    _same=$(_pg_owned_pid 2>/dev/null) || _same=''
    [ "$_same" = "$_p" ] || break
    sleep 0.25
    _i=$((_i+1))
  done
  _same=$(_pg_owned_pid 2>/dev/null) || _same=''
  if [ "$_same" = "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    # Revalidate identity immediately before SIGKILL.
    _same=$(_pg_owned_pid 2>/dev/null) || _same=''
    [ "$_same" = "$_p" ] && kill -KILL "$_p" 2>/dev/null || :
  fi
  _i=0
  while [ "$_i" -lt 10 ] && kill -0 "$_p" 2>/dev/null; do sleep 0.2; _i=$((_i+1)); done
  _same=$(_pg_owned_pid 2>/dev/null) || _same=''
  if [ "$_same" = "$_p" ] && kill -0 "$_p" 2>/dev/null; then
    _pg_log 'stop timed out; retained PID marker for safe retry'; return 1
  fi
  _pg_remove_pid_marker_if_matches "$_p"
  _pg_log 'stopped managed engine'
  return 0
}
_pg_ensure() {
  mkdir -p "$STATE" "$WORK" || return 1
  chmod 700 "$STATE" "$WORK" 2>/dev/null || :
  _pg_check_binary || { _pg_stop || :; return 1; }
  # Ensure the local recursive resolver before starting the filter front end.
  # If Unbound is unavailable or its uncached recursive probe fails, do not
  # bring up AdGuard Home and do not install DNS redirection.
  if ! sh "$MODDIR/scripts/unbound.sh" ensure "$MODDIR" "$PG" >> "$LOG" 2>&1; then
    _pg_log 'local recursive Unbound is not healthy; DNS interception remains disabled'
    _pg_stop || :
    return 1
  fi
  _tmp="$CFG.tmp.$$"
  _pg_render_config > "$_tmp" || { rm -f "$_tmp"; return 1; }
  chmod 600 "$_tmp" 2>/dev/null || :
  # Validate with the actual pinned engine before changing its active config.
  if ! "$BIN" --config "$_tmp" --work-dir "$WORK" --check-config >> "$LOG" 2>&1; then
    _pg_log 'generated configuration rejected by --check-config'; rm -f "$_tmp"; return 1
  fi
  _p=$(_pg_owned_pid 2>/dev/null) || _p=''
  if [ -n "$_p" ] && [ -s "$CFG" ] && cmp -s "$_tmp" "$CFG"; then
    rm -f "$_tmp"
    if _pg_dns_probe; then return 0; fi
    _pg_stop || return 1
    return 1
  fi
  if [ -n "$_p" ]; then _pg_stop || { rm -f "$_tmp"; return 1; }; fi
  if ! mv -f "$_tmp" "$CFG"; then rm -f "$_tmp"; return 1; fi
  chmod 600 "$CFG" 2>/dev/null || :
  nohup "$BIN" --config "$CFG" --work-dir "$WORK" --logfile "$LOG" >/dev/null 2>&1 &
  _new=$!
  printf '%s\n' "$_new" > "$PIDFILE.tmp.$$" || { rm -f "$PIDFILE.tmp.$$" 2>/dev/null || :; kill "$_new" 2>/dev/null || :; return 1; }
  chmod 600 "$PIDFILE.tmp.$$" 2>/dev/null || :
  mv -f "$PIDFILE.tmp.$$" "$PIDFILE" || { rm -f "$PIDFILE.tmp.$$" 2>/dev/null || :; kill "$_new" 2>/dev/null || :; return 1; }
  _i=0
  _same=''
  while [ "$_i" -lt 12 ]; do
    _same=$(_pg_owned_pid 2>/dev/null) || _same=''
    [ "$_same" = "$_new" ] && break
    if ! kill -0 "$_new" 2>/dev/null; then
      _pg_log 'process exited during startup'; _pg_remove_pid_marker_if_matches "$_new"; return 1
    fi
    _i=$((_i+1)); sleep 1
  done
  if [ "$_same" = "$_new" ] && _pg_dns_probe; then
    _pg_log 'ready; loopback DNS resolution probe succeeded'
    return 0
  fi
  _pg_log 'startup/health timeout; stopping engine and leaving DNS redirection disabled'
  _pg_stop || :
  return 1
}

case "$ACTION" in
  render-config)
    _pg_render_config
    ;;
  ensure)
    if _pg_ensure; then exit 0; fi
    sh "$MODDIR/scripts/unbound.sh" stop "$MODDIR" "$PG" >> "$LOG" 2>&1 || :
    exit 1
    ;;
  stop)
    if _pg_stop; then
      sh "$MODDIR/scripts/unbound.sh" stop "$MODDIR" "$PG"
    else
      exit 1
    fi
    ;;
  status)
    if _p=$(_pg_owned_pid 2>/dev/null); then
      if sh "$MODDIR/scripts/unbound.sh" status "$MODDIR" "$PG" >/dev/null 2>&1 && _pg_dns_probe; then echo 'ready'; exit 0; fi
      echo 'running-unhealthy'; exit 1
    fi
    echo 'stopped'; exit 1
    ;;
  *) echo 'usage: adguardhome.sh {render-config|ensure|stop|status} [module_dir] [data_dir]' >&2; exit 64 ;;
esac
