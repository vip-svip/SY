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
_root_hints_valid() {
  _hints_file=$1
  [ -f "$_hints_file" ] && [ ! -L "$_hints_file" ] && [ -s "$_hints_file" ] || return 1
  awk '
    function valid_ipv4(v,n,a,i,first,second) {
      n=split(v,a,".")
      if(n!=4)return 0
      for(i=1;i<=4;i++)
        if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 ||
           (a[i]!="0" && a[i]~/^0/))return 0
      first=a[1]+0;second=a[2]+0
      if(first==0 || first==10 || first==127 || first>=224 ||
         (first==169 && second==254) ||
         (first==172 && second>=16 && second<=31) ||
         (first==192 && second==168) ||
         (first==100 && second>=64 && second<=127) ||
         (first==255 && second==255 && a[3]+0==255 && a[4]+0==255))return 0
      return 1
    }
    function valid_ipv6(v,pos,left,right,count,i,n,a,b,first) {
      if(v=="" || index(v,":")==0 || v~/[^0-9A-Fa-f:]/ || v~/:::/)return 0
      pos=index(v,"::")
      if(pos && index(substr(v,pos+2),"::"))return 0
      count=0
      first=""
      if(pos) {
        left=substr(v,1,pos-1)
        right=substr(v,pos+2)
        if(left!="") {
          n=split(left,a,":")
          for(i=1;i<=n;i++)
            if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/)return 0
          count+=n
          first=a[1]
        }
        if(right!="") {
          n=split(right,b,":")
          for(i=1;i<=n;i++)
            if(b[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/)return 0
          count+=n
          if(first=="")first=b[1]
        }
        if(count>=8)return 0
      } else {
        n=split(v,a,":")
        if(n!=8)return 0
        for(i=1;i<=n;i++)
          if(a[i]!~/^[0-9A-Fa-f][0-9A-Fa-f]?[0-9A-Fa-f]?[0-9A-Fa-f]?$/)return 0
        first=a[1]
      }
      # Root server AAAA records must be globally scoped unicast (2000::/3).
      if(tolower(substr(first,1,1))!="2" && tolower(substr(first,1,1))!="3")return 0
      return 1
    }
    BEGIN {
      split("A B C D E F G H I J K L M",letters," ")
    }
    {
      line=$0
      sub(/;.*/,"",line)
      gsub(/^[ \t]+/,"",line)
      gsub(/[ \t]+$/,"",line)
      if(line=="")next
      n=split(line,f,/[ \t]+/)
      if(f[1]=="$TTL") {
        ttl_directive++
        if(n!=2 || f[2]!~/^[0-9]+$/ || f[2]+0>4294967295)bad=1
        next
      }
      idx=2
      if(f[idx]~/^[0-9]+$/) {
        if(f[idx]+0>4294967295)bad=1
        idx++
      }
      if(toupper(f[idx])=="IN")idx++
      if(n!=idx+1) {bad=1;next}
      type=toupper(f[idx])
      owner=toupper(f[1])
      sub(/[.]$/,"",owner)
      if(owner=="." && type=="NS") {
        target=toupper(f[idx+1])
        sub(/[.]$/,"",target)
        if(target!~/^[A-M][.]ROOT-SERVERS[.]NET$/ || ns[target]++)bad=1
        next
      }
      if(owner~/^[A-M][.]ROOT-SERVERS[.]NET$/ && type=="A") {
        if(!valid_ipv4(f[idx+1]) || addr[owner]++)bad=1
        next
      }
      if(owner~/^[A-M][.]ROOT-SERVERS[.]NET$/ && type=="AAAA") {
        if(!valid_ipv6(f[idx+1]) || addr6[owner]++)bad=1
        next
      }
      bad=1
    }
    END {
      if(ttl_directive>1)bad=1
      for(i=1;i<=13;i++) {
        name=letters[i] ".ROOT-SERVERS.NET"
        if(!ns[name] || !addr[name])bad=1
      }
      if(bad)exit 1
    }
  ' "$_hints_file"
}
_check_files() {
  [ -x "$BIN" ] && [ -x "$CHECKBIN" ] && [ -x "$ANCHOR" ] && [ -x "$PROBE" ] || { _log 'unbound runtime/checker/anchor/probe missing or not executable'; return 1; }
  _hash "$BIN" "$ROOT/unbound.sha256" || return 1
  _hash "$CHECKBIN" "$ROOT/unbound-checkconf.sha256" || return 1
  _hash "$ANCHOR" "$ROOT/unbound-anchor.sha256" || return 1
  _hash "$PROBE" "$ROOT/fx-dns-probe.sha256" || return 1
  _hash "$ROOT_HINTS" "$ROOT/root.hints.sha256" || return 1
  _hash "$ROOT_KEY_SEED" "$ROOT/root.key.seed.sha256" || return 1
  _root_hints_valid "$ROOT_HINTS" || { _log 'root hints file has missing or malformed root-server records'; return 1; }
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
  _ub_prefetch_key=$(_unbound_runtime_value UNBOUND_PREFETCH_KEY) || return 1
  _ub_qname_minimisation=$(_unbound_runtime_value UNBOUND_QNAME_MINIMISATION) || return 1
  _ub_msg_cache_size=$(_unbound_runtime_value UNBOUND_MSG_CACHE_SIZE) || return 1
  _ub_rrset_cache_size=$(_unbound_runtime_value UNBOUND_RRSET_CACHE_SIZE) || return 1
  _ub_key_cache_size=$(_unbound_runtime_value UNBOUND_KEY_CACHE_SIZE) || return 1
  _ub_neg_cache_size=$(_unbound_runtime_value UNBOUND_NEG_CACHE_SIZE) || return 1
  _ub_num_threads=$(_unbound_runtime_value UNBOUND_NUM_THREADS) || return 1
  case "$_ub_num_threads" in ''|*[!0-9]*|0)
    _log 'Unbound worker count is missing or invalid'
    return 1
    ;;
  esac
  _ub_online_cores=$(awk -F, '
    {
      for (i=1; i<=NF; i++) {
        split($i, range, "-")
        first=range[1]+0
        last=(range[2]=="" ? first : range[2]+0)
        if (range[1] ~ /^[0-9]+$/ && last>=first) total+=last-first+1
      }
    }
    END { if (total>0) print total }
  ' /sys/devices/system/cpu/online 2>/dev/null)
  case "$_ub_online_cores" in ''|*[!0-9]*|0)
    _ub_online_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null | tr -d '[:space:]') ;;
  esac
  case "$_ub_online_cores" in ''|*[!0-9]*|0)
    _ub_online_cores=$(awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo 2>/dev/null) ;;
  esac
  case "$_ub_online_cores" in ''|*[!0-9]*|0) _ub_online_cores=1 ;; esac
  [ "$_ub_num_threads" -le "$_ub_online_cores" ] 2>/dev/null || {
    _log 'configured Unbound worker count exceeds currently online CPU cores'
    return 1
  }
  for _ub_cache_size in "$_ub_msg_cache_size" "$_ub_rrset_cache_size" "$_ub_key_cache_size" "$_ub_neg_cache_size"; do
    case "$_ub_cache_size" in ''|*[!0-9kKmMgG]*) _log 'Unbound cache pool size has invalid syntax'; return 1 ;; esac
    _ub_cache_size_number=$_ub_cache_size
    case "$_ub_cache_size_number" in *[kKmMgG]) _ub_cache_size_number=${_ub_cache_size_number%?} ;; esac
    case "$_ub_cache_size_number" in ''|*[!0-9]*) _log 'Unbound cache pool size has invalid numeric value'; return 1 ;; esac
  done
  case "$_ub_serve_expired:$_ub_prefetch:$_ub_prefetch_key:$_ub_qname_minimisation" in
    0:0:0:0|0:0:0:1|0:0:1:0|0:0:1:1|0:1:0:0|0:1:0:1|0:1:1:0|0:1:1:1|1:0:0:0|1:0:0:1|1:0:1:0|1:0:1:1|1:1:0:0|1:1:0:1|1:1:1:0|1:1:1:1) : ;;
    *) _log 'Unbound runtime boolean setting is invalid'; return 1 ;;
  esac
  case "$_ub_serve_expired" in 1) _ub_serve_expired_yaml=yes ;; 0) _ub_serve_expired_yaml=no ;; esac
  case "$_ub_prefetch" in 1) _ub_prefetch_yaml=yes ;; 0) _ub_prefetch_yaml=no ;; esac
  case "$_ub_prefetch_key" in 1) _ub_prefetch_key_yaml=yes ;; 0) _ub_prefetch_key_yaml=no ;; esac
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
  num-threads: $_ub_num_threads
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
  prefetch-key: $_ub_prefetch_key_yaml
  serve-expired: $_ub_serve_expired_yaml
  serve-expired-ttl: $_ub_serve_expired_ttl
  serve-expired-reply-ttl: $_ub_serve_expired_reply_ttl
  serve-expired-client-timeout: $_ub_serve_expired_client_timeout
  edns-buffer-size: 1232
  max-udp-size: 1232
  msg-cache-size: $_ub_msg_cache_size
  rrset-cache-size: $_ub_rrset_cache_size
  key-cache-size: $_ub_key_cache_size
  neg-cache-size: $_ub_neg_cache_size
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



_anchor_status() {
  _path_components_are_safe "$STATE" || { echo "unsafe Unbound state directory" >&2; return 21; }
  _anchor_state=missing
  _anchor_bytes=0
  _anchor_age=unknown
  _refresh_route=system_default
  _resolver_state=unknown
  _root_hints_state=missing
  _root_hints_bytes=0
  if [ -L "$STATE" ] || { [ -e "$STATE" ] && [ ! -d "$STATE" ]; }; then
    _anchor_state=unsafe
  elif [ -d "$STATE" ]; then
    if ! _safe_file_or_absent "$STATE/root.key"; then
      _anchor_state=unsafe
    elif [ -s "$STATE/root.key" ]; then
      _anchor_bytes=$(wc -c < "$STATE/root.key" 2>/dev/null | tr -d ' ')
      case "$_anchor_bytes" in ''|*[!0-9]*) _anchor_bytes=unknown ;; esac
      if grep -Eq '^\.[[:space:]]+IN[[:space:]]+DNSKEY[[:space:]]+257[[:space:]]+3[[:space:]]+8[[:space:]]' "$STATE/root.key" 2>/dev/null; then
        _anchor_state=valid
        if [ -n "$(find "$STATE/root.key" -mtime +14 -print -quit 2>/dev/null)" ]; then _anchor_age=stale; else _anchor_age=current; fi
      else
        _anchor_state=invalid
      fi
    fi
  fi
  if ! _safe_file_or_absent "$ROOT_HINTS" || ! _safe_file_or_absent "$ROOT/root.hints.sha256"; then
    _root_hints_state=unsafe
  elif [ ! -s "$ROOT_HINTS" ] || [ ! -s "$ROOT/root.hints.sha256" ]; then
    _root_hints_state=missing
  else
    _root_hints_bytes=$(wc -c < "$ROOT_HINTS" 2>/dev/null | tr -d ' ')
    case "$_root_hints_bytes" in ''|*[!0-9]*) _root_hints_bytes=unknown ;; esac
    if _hash "$ROOT_HINTS" "$ROOT/root.hints.sha256"; then
      _root_hints_state=valid
    else
      _root_hints_state=invalid
    fi
  fi
  if [ -L "$EGRESS" ]; then
    _refresh_route=unsafe
  elif [ -e "$EGRESS" ]; then
    if [ -f "$EGRESS" ]; then _refresh_route=vpn_bound; else _refresh_route=unsafe; fi
  fi
  if _p=$(_owned_pid 2>/dev/null); then _resolver_state=running; else _resolver_state=stopped; fi
  echo FXYUNBOUNDANCHOR2
  printf 'anchor_state=%s\n' "$_anchor_state"
  printf 'anchor_bytes=%s\n' "$_anchor_bytes"
  printf 'anchor_age=%s\n' "$_anchor_age"
  printf 'refresh_route=%s\n' "$_refresh_route"
  printf 'resolver_state=%s\n' "$_resolver_state"
  printf 'root_hints_state=%s\n' "$_root_hints_state"
  printf 'root_hints_bytes=%s\n' "$_root_hints_bytes"
}
_refresh_anchor() {
  _prepare_state_dirs || return 20
  [ -x "$ANCHOR" ] || { echo "Unbound trust-anchor helper is missing or not executable" >&2; return 20; }
  [ -s "$STATE/root.key" ] || { echo "initialize the recursive resolver before refreshing its trust anchor" >&2; return 2; }
  grep -Eq '^\.[[:space:]]+IN[[:space:]]+DNSKEY[[:space:]]+257[[:space:]]+3[[:space:]]+8[[:space:]]' "$STATE/root.key" 2>/dev/null || {
    echo "current trust anchor is invalid; refusing an in-place refresh" >&2
    return 2
  }
  [ ! -e "$EGRESS" ] && [ ! -L "$EGRESS" ] || {
    echo "manual trust-anchor refresh refused while Unbound is VPN-egress-bound; online RFC5011 maintenance remains enabled" >&2
    return 11
  }
  _p=$(_owned_pid 2>/dev/null) || _p=''
  [ -z "$_p" ] || {
    echo "manual trust-anchor refresh refused while the recursive resolver is running; Unbound maintains RFC5011 state online" >&2
    return 11
  }
  command -v timeout >/dev/null 2>&1 || {
    echo "timeout helper is unavailable; refusing an unbounded trust-anchor refresh" >&2
    return 20
  }
  _anchor_backup=$(_new_private_temp "$STATE/root.key.manual-refresh.XXXXXX") || return 1
  cp "$STATE/root.key" "$_anchor_backup" 2>/dev/null || { rm -f "$_anchor_backup"; return 1; }
  _anchor_rc=0
  timeout 5 "$ANCHOR" -a "$STATE/root.key" >> "$LOG" 2>&1 || _anchor_rc=$?
  if [ "$_anchor_rc" -ne 0 ] || ! grep -Eq '^\.[[:space:]]+IN[[:space:]]+DNSKEY[[:space:]]+257[[:space:]]+3[[:space:]]+8[[:space:]]' "$STATE/root.key" 2>/dev/null; then
    if ! mv -f "$_anchor_backup" "$STATE/root.key" 2>/dev/null; then
      _log 'manual trust-anchor refresh failed and previous anchor rollback failed; preserving recovery copy'
      echo "trust-anchor refresh failed and rollback could not be confirmed; recovery copy retained" >&2
      return 1
    fi
    _log 'manual trust-anchor refresh failed; previous trust anchor restored'
    echo "trust-anchor refresh failed; previous anchor restored" >&2
    return 1
  fi
  rm -f "$_anchor_backup" 2>/dev/null || return 1
  _log 'manual bounded trust-anchor refresh completed'
  _anchor_status
  printf 'refresh=completed\n'
}

_refresh_root_hints() {
  _prepare_state_dirs || return 20
  _path_components_are_safe "$ROOT" && [ -d "$ROOT" ] && [ ! -L "$ROOT" ] || {
    echo "Unbound engine directory is missing or unsafe" >&2
    return 21
  }
  _safe_file_or_absent "$ROOT_HINTS" && _safe_file_or_absent "$ROOT/root.hints.sha256" || {
    echo "Root Hints destination or checksum sidecar is unsafe" >&2
    return 21
  }
  [ ! -e "$EGRESS" ] && [ ! -L "$EGRESS" ] || {
    echo "Root Hints refresh refused while Unbound VPN-egress binding is present" >&2
    return 11
  }
  _p=$(_owned_pid 2>/dev/null) || _p=''
  [ -z "$_p" ] || {
    echo "Root Hints refresh refused while Unbound is running; stop the resolver first" >&2
    return 11
  }
  command -v timeout >/dev/null 2>&1 || {
    echo "timeout helper is unavailable; refusing an unbounded Root Hints download" >&2
    return 20
  }
  _download_tmp=$(_new_private_temp "$ROOT/root.hints.download.XXXXXX") || return 1
  _checksum_tmp=$(_new_private_temp "$ROOT/root.hints.sha256.download.XXXXXX") || {
    rm -f "$_download_tmp"; return 1;
  }
  _root_backup=$(_new_private_temp "$ROOT/root.hints.backup.XXXXXX") || {
    rm -f "$_download_tmp" "$_checksum_tmp"; return 1;
  }
  _checksum_backup=$(_new_private_temp "$ROOT/root.hints.sha256.backup.XXXXXX") || {
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup"; return 1;
  }
  if command -v curl >/dev/null 2>&1; then
    if ! timeout 25 curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --connect-timeout 6 --max-time 20 \
        --output "$_download_tmp" "https://www.internic.net/domain/named.root"; then
      rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
      echo "download from the official HTTPS Root Hints source failed" >&2
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if ! timeout 25 wget --https-only --quiet --output-document="$_download_tmp" \
        "https://www.internic.net/domain/named.root"; then
      rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
      echo "HTTPS-only wget download is unavailable or failed" >&2
      return 1
    fi
  else
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    echo "curl or HTTPS-only wget is required to refresh Root Hints" >&2
    return 20
  fi
  _root_hints_valid "$_download_tmp" || {
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    echo "downloaded Root Hints failed the 13-root-server NS/A structure check" >&2
    return 2
  }
  if command -v sha256sum >/dev/null 2>&1; then
    _new_hash=$(sha256sum "$_download_tmp" 2>/dev/null | awk '{print tolower($1)}')
  elif command -v toybox >/dev/null 2>&1; then
    _new_hash=$(toybox sha256sum "$_download_tmp" 2>/dev/null | awk '{print tolower($1)}')
  else
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    echo "SHA-256 utility is unavailable; Root Hints were not changed" >&2
    return 20
  fi
  case "$_new_hash" in ''|*[!a-f0-9]*)
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    echo "invalid SHA-256 result" >&2
    return 1
    ;;
  esac
  _hash_length=$(printf '%s' "$_new_hash" | wc -c | tr -d ' ')
  [ "$_hash_length" = 64 ] || {
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    echo "invalid SHA-256 result" >&2
    return 1
  }
  printf '%s  root.hints\n' "$_new_hash" > "$_checksum_tmp" || {
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    return 1
  }
  chmod 644 "$_download_tmp" "$_checksum_tmp" || {
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    return 1
  }
  _had_root=0
  _had_checksum=0
  if [ -e "$ROOT_HINTS" ]; then
    [ -f "$ROOT_HINTS" ] && [ ! -L "$ROOT_HINTS" ] &&
      cp "$ROOT_HINTS" "$_root_backup" 2>/dev/null || {
        rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
        echo "cannot preserve existing Root Hints for rollback" >&2
        return 1
      }
    _had_root=1
  fi
  if [ -e "$ROOT/root.hints.sha256" ]; then
    [ -f "$ROOT/root.hints.sha256" ] && [ ! -L "$ROOT/root.hints.sha256" ] &&
      cp "$ROOT/root.hints.sha256" "$_checksum_backup" 2>/dev/null || {
        rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
        echo "cannot preserve existing Root Hints checksum for rollback" >&2
        return 1
      }
    _had_checksum=1
  fi
  mv -f "$_download_tmp" "$ROOT_HINTS" || {
    rm -f "$_download_tmp" "$_checksum_tmp" "$_root_backup" "$_checksum_backup"
    echo "cannot atomically publish updated Root Hints" >&2
    return 1
  }
  if ! mv -f "$_checksum_tmp" "$ROOT/root.hints.sha256"; then
    _rollback_ok=1
    if [ "$_had_root" = 1 ]; then
      mv -f "$_root_backup" "$ROOT_HINTS" || _rollback_ok=0
    else
      rm -f "$ROOT_HINTS" || _rollback_ok=0
    fi
    if [ "$_had_checksum" = 1 ]; then
      mv -f "$_checksum_backup" "$ROOT/root.hints.sha256" || _rollback_ok=0
    else
      rm -f "$ROOT/root.hints.sha256" || _rollback_ok=0
    fi
    if [ "$_rollback_ok" = 1 ]; then
      rm -f "$_root_backup" "$_checksum_backup"
    else
      _log 'Root Hints update failed and rollback is incomplete; recovery copies retained'
      echo "Root Hints checksum publish failed and previous data could not be fully restored; recovery files retained" >&2
      return 1
    fi
    rm -f "$_root_backup" "$_checksum_backup"
    echo "Root Hints checksum publish failed; previous data restored" >&2
    return 1
  fi
  if ! _hash "$ROOT_HINTS" "$ROOT/root.hints.sha256" || ! _root_hints_valid "$ROOT_HINTS"; then
    _rollback_ok=1
    if [ "$_had_root" = 1 ]; then mv -f "$_root_backup" "$ROOT_HINTS" || _rollback_ok=0
    else rm -f "$ROOT_HINTS" || _rollback_ok=0; fi
    if [ "$_had_checksum" = 1 ]; then mv -f "$_checksum_backup" "$ROOT/root.hints.sha256" || _rollback_ok=0
    else rm -f "$ROOT/root.hints.sha256" || _rollback_ok=0; fi
    if [ "$_rollback_ok" != 1 ]; then
      _log 'Root Hints post-publish verification failed and rollback is incomplete; recovery copies retained'
      echo "Root Hints post-publish verification failed; rollback incomplete and recovery copies retained" >&2
      return 1
    fi
    rm -f "$_root_backup" "$_checksum_backup"
    echo "Root Hints post-publish verification failed; previous data restored" >&2
    return 1
  fi
  rm -f "$_root_backup" "$_checksum_backup"
  _log "Root Hints refreshed from official InterNIC HTTPS source (sha256 $_new_hash)"
  _anchor_status
  printf 'root_hints_refresh=updated\n'
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
  anchor-status) _with_lifecycle_lock _anchor_status ;;
  anchor-refresh) _with_lifecycle_lock _refresh_anchor ;;
  root-hints-refresh) _with_lifecycle_lock _refresh_root_hints ;;
  ensure) _with_lifecycle_lock _ensure ;;
  stop) _with_lifecycle_lock _stop ;;
  status)
    if _p=$(_owned_pid 2>/dev/null); then
      if _probe; then echo ready; exit 0; fi
      echo running-unhealthy; exit 1
    fi
    echo stopped; exit 1
    ;;
  *) echo 'usage: unbound.sh {render-config|anchor-status|anchor-refresh|root-hints-refresh|ensure|stop|status} [module_dir] [data_dir]' >&2; exit 64 ;;
esac
