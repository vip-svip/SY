#!/system/bin/sh
# DNS Root Proxy fallback over a validated third-party Android VPN.
# Status probes are expected to fail open when the validated route disappears.
# Uses FX's existing AdGuard Home + Unbound; never creates a VpnService.
# Every uncertain state removes only FXYRP-owned rules and fails open.
set -eu

MP=${MP:-}
if [ -z "$MP" ]; then
  for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do
    if [ -s "$d/module.prop" ] && grep -q '^id=privacyguard$' "$d/module.prop" 2>/dev/null; then
      MP="$d"; break
    fi
  done
fi
[ -n "$MP" ] && [ -s "$MP/module.prop" ] || { echo "FX module is not installed" >&2; exit 20; }
[ -s "$MP/scripts/util.sh" ] || { echo "FX config utilities missing" >&2; exit 21; }
. "$MP/scripts/util.sh"

PG=${PG:-/data/adb/privacyguard}
CONF=${CONF:-$PG/settings.conf}
ACTIVE="$PG/yulong-root-proxy-active"
ACTIVE_META="$PG/yulong-root-proxy-active.meta"
EGRESS="$PG/unbound-vpn-egress-ip"
LOCK="$PG/yulong-root-proxy.lock"
LOG="$PG/yulong-root-proxy.log"
_RPROXY_TEMP=
_reject_symlink_components() {
  _symlink_path=$1
  while [ -n "$_symlink_path" ] && [ "$_symlink_path" != "/" ]; do
    [ ! -L "$_symlink_path" ] || return 1
    case "$_symlink_path" in
      */*) _symlink_parent=${_symlink_path%/*}; [ -n "$_symlink_parent" ] || _symlink_parent=/ ;;
      *) break ;;
    esac
    [ "$_symlink_parent" != "$_symlink_path" ] || break
    _symlink_path=$_symlink_parent
  done
  return 0
}
_validate_real_parent_chain() {
  _state_candidate=$1
  case "$_state_candidate" in /*) : ;; *) return 1 ;; esac
  case "$_state_candidate" in /|*/|*//* ) return 1 ;; esac
  _state_final=${_state_candidate##*/}
  case "$_state_final" in ''|.|..) return 1 ;; esac
  _state_parent=${_state_candidate%/*}
  [ -n "$_state_parent" ] || _state_parent=/
  _state_rest=${_state_parent#/}
  _state_walk=
  while [ -n "$_state_rest" ]; do
    case "$_state_rest" in
      */*) _state_component=${_state_rest%%/*}; _state_rest=${_state_rest#*/} ;;
      *) _state_component=$_state_rest; _state_rest= ;;
    esac
    case "$_state_component" in ''|.|..) return 1 ;; esac
    _state_walk="$_state_walk/$_state_component"
    [ -d "$_state_walk" ] && [ ! -L "$_state_walk" ] || return 1
  done
  return 0
}
_validate_real_parent_chain "$PG" || {
  echo "Root Proxy state directory has a missing or unsafe parent" >&2
  exit 22
}
[ ! -L "$PG" ] || { echo "Root Proxy state directory is unsafe" >&2; exit 21; }
if [ ! -e "$PG" ]; then mkdir "$PG" || { echo "cannot create Root Proxy state directory" >&2; exit 21; }; fi
[ -d "$PG" ] && [ ! -L "$PG" ] || { echo "Root Proxy state directory is missing or unsafe" >&2; exit 21; }
[ "$CONF" = "$PG/settings.conf" ] || {
  echo "Root Proxy settings path must be inside the private state directory" >&2
  exit 21
}
for _state_path in "$PG" "$CONF" "$ACTIVE" "$ACTIVE_META" "$EGRESS" "$LOCK" "$LOG"; do
  _reject_symlink_components "$_state_path" || {
    echo "unsafe Root Proxy state path: $_state_path" >&2
    exit 22
  }
done
[ -f "$CONF" ] || { echo "Root Proxy settings.conf missing or unsafe" >&2; exit 21; }
[ ! -e "$LOCK" ] || [ -f "$LOCK" ] || [ -d "$LOCK" ] || { echo "Root Proxy lock path is not a regular file or legacy lock directory" >&2; exit 22; }
for _state_file in "$ACTIVE" "$ACTIVE_META" "$EGRESS" "$LOG"; do
  [ ! -e "$_state_file" ] || [ -f "$_state_file" ] || {
    echo "Root Proxy refuses a non-regular state file: $_state_file" >&2
    exit 22
  }
done

_log() {
  [ ! -e "$LOG" ] || [ -f "$LOG" ] || return 0
  printf '[%s] yulong-root-proxy: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :
}
_valid_uid() { case "${1:-}" in ''|*[!0-9]*|0) return 1;; *) return 0;; esac; }
_valid_if() {
  # Linux IFNAMSIZ includes the trailing NUL, so an interface name is at
  # most 15 ASCII bytes. Reject overlong names before passing them to ip.
  case "${1:-}" in ''|.|..|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  [ "${#1}" -le 15 ]
}
_valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 {ok=0; exit}
    {
      ok=1
      for (i=1; i<=4; i++) {
        if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255 ||
            ($i != "0" && $i ~ /^0/)) ok=0
      }
      first=$1+0
      second=$2+0
      # A VPN egress source must be a unicast interface address, not an
      # unspecified, loopback, link-local, multicast or reserved address.
      if (first==0 || first==127 || first>=224 ||
          (first==169 && second==254)) ok=0
    }
    END {exit(ok ? 0 : 1)}
  '
}
_local_dns_probe_endpoint() {
  _server="$1"
  _probe_output=$(timeout 5 nslookup example.com "$_server" 2>&1) || return 1
  # Ignore the resolver's own Server/Address header and require an answer
  # address associated with the queried name.
  _probe_answers=$(printf '%s\n' "$_probe_output" | awk '
    tolower($0) ~ /^[[:space:]]*name:[[:space:]]*example[.]com([.]?)([[:space:]]|$)/ {
      answer=1; next
    }
    answer && tolower($0) ~ /^[[:space:]]*address([[:space:]]+[0-9]+)?:[[:space:]]*[0-9]+([.][0-9]+){3}([[:space:]]|$)/ {
      print $NF
    }
  ')
  for _probe_ip in $_probe_answers; do
    _valid_ipv4 "$_probe_ip" && return 0
  done
  return 1
}
_local_dns_probe() {
  command -v nslookup >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 || return 1
  # Both families are redirected to loopback by Root Proxy; validate both
  # listeners before attaching either OUTPUT chain.
  _local_dns_probe_endpoint 127.0.0.1 || return 1
  _local_dns_probe_endpoint ::1 || return 1
}
_is_enabled() {
  [ "$(pg_get vpn_external_dns_proxy 1 2>/dev/null)" = "1" ] \
    && [ "$(pg_get vpn_external_compat 1 2>/dev/null)" = "1" ] \
    && [ "$(pg_get dns_forward 1 2>/dev/null)" = "1" ]
}
_valid_package() {
  case "${1:-}" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'
}
_list_whitelist_packages() {
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || return 1
  awk -F'|' '
    $0=="[list:yulong_root_proxy_whitelist]" {inside=1; next}
    /^\[/ {inside=0}
    inside && $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ &&
      ($2=="0" || $2=="1") && $2=="1" {print $1}
  ' "$CONF"
}
_whitelist_set_value() {
  _package="$1"; _state="$2"
  _valid_package "$_package" && { [ "$_state" = 0 ] || [ "$_state" = 1 ]; } || return 2
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || { _log "settings.conf is missing or unsafe"; return 21; }
  _RPROXY_TEMP=$(mktemp "$CONF.yulong-rootproxy-whitelist.XXXXXX") || return 1
  awk -F'|' -v pkg="$_package" -v state="$_state" '
    BEGIN {inside=0; seen=0; written=0}
    $0=="[list:yulong_root_proxy_whitelist]" {inside=1; seen=1; print; next}
    /^\[/ {
      if(inside && state=="1" && !written) {print pkg "|1"; written=1}
      inside=0; print; next
    }
    inside && $1==pkg {
      if(state=="1" && !written) {print pkg "|1"; written=1}
      next
    }
    {print}
    END {
      if(inside && state=="1" && !written) print pkg "|1"
      if(!seen && state=="1") {print ""; print "[list:yulong_root_proxy_whitelist]"; print pkg "|1"}
    }
  ' "$CONF" > "$_RPROXY_TEMP" || { rm -f "$_RPROXY_TEMP"; _RPROXY_TEMP=; return 1; }
  if [ -s "$_RPROXY_TEMP" ] && [ ! -L "$CONF" ] && chmod 600 "$_RPROXY_TEMP" && mv -f "$_RPROXY_TEMP" "$CONF"; then
    _RPROXY_TEMP=
    return 0
  fi
  rm -f "$_RPROXY_TEMP"; _RPROXY_TEMP=
  return 1
}
_resolve_whitelist_uids() {
  _packages=$(_list_whitelist_packages) || return 1
  [ -n "$_packages" ] || return 0
  _snapshot=$(cmd package list packages -U 2>/dev/null) || { _log "cannot read PackageManager UID snapshot for Root Proxy whitelist"; return 1; }
  [ -n "$_snapshot" ] || { _log "PackageManager returned an empty UID snapshot"; return 1; }
  printf '%s\n' "$_snapshot" | awk '
    $1 ~ /^package:[A-Za-z0-9_.-]+$/ {
      for(i=2;i<=NF;i++) if($i ~ /^uid:[0-9]+$/) {valid=1; break}
    }
    END {exit !valid}
  ' || { _log "PackageManager UID snapshot is malformed; fail-open"; return 1; }
  _resolved=""
  while IFS= read -r _package; do
    [ -n "$_package" ] || continue
    _uid=$(printf '%s\n' "$_snapshot" | awk -v wanted="package:$_package" '
      $1==wanted {for(i=2;i<=NF;i++) if($i ~ /^uid:[0-9]+$/) {sub(/^uid:/,"",$i); print $i; exit}}
    ')
    [ -n "$_uid" ] || continue
    case "$_uid" in *[!0-9]*|0) _log "invalid current UID for whitelist package $_package"; return 1 ;; esac
    case "
$_resolved
" in *"
$_uid
"*) ;; *)
      [ -n "$_resolved" ] && _resolved="$_resolved
"
      _resolved="$_resolved$_uid"
    ;; esac
  done <<EOF
$_packages
EOF
  printf '%s\n' "$_resolved"
}
_remove_hook() {
  _bin="$1"; _chain="$2"
  while "$_bin" -t nat -D OUTPUT -j "$_chain" >/dev/null 2>&1; do :; done
  if "$_bin" -t nat -C OUTPUT -j "$_chain" >/dev/null 2>&1; then
    _log "ERROR: FX-owned OUTPUT hook remains attached: $_chain"
    return 1
  fi
  return 0
}
_clear_chain() {
  _bin="$1"; _chain="$2"
  # Removing the OUTPUT jump is the safety-critical operation. An orphaned
  # private chain is inert; a surviving jump is not, so propagate that failure.
  _remove_hook "$_bin" "$_chain" || return 1
  "$_bin" -t nat -F "$_chain" >/dev/null 2>&1 || :
  "$_bin" -t nat -X "$_chain" >/dev/null 2>&1 || :
  return 0
}
_clear_all() {
  _clear_failed=0
  for c in FXYRP4_A FXYRP4_B; do _clear_chain iptables "$c" || _clear_failed=1; done
  for c in FXYRP6_A FXYRP6_B; do _clear_chain ip6tables "$c" || _clear_failed=1; done
  if [ "$_clear_failed" = 1 ]; then
    _log "ERROR: one or more FX-owned DNS OUTPUT hooks could not be detached; preserving state markers for retry"
    return 1
  fi
  # Keep the egress marker until the shared Unbound process has either
  # reloaded without its VPN binding or been confirmed stopped. If both
  # operations fail, the marker is the recovery signal for the next retry.
  rm -f "$ACTIVE" "$ACTIVE_META" "$EGRESS.tmp."* 2>/dev/null || {
    _log "ERROR: unable to remove Root Proxy active markers after redirect cleanup"
    return 1
  }
  return 0
}
_stop_engines() {
  # These resolver daemons are shared with the independent local-DNS feature.
  # Root Proxy owns only its DNS redirection rules; stopping it must not tear
  # down a resolver that remains enabled outside the external-VPN fallback.
  _engine_failed=0
  if [ "$(pg_get dns_engine_adguardhome 0 2>/dev/null)" != "1" ]; then
    if ! sh "$MP/scripts/adguardhome.sh" stop "$MP" "$PG" >> "$LOG" 2>&1; then
      _log "ERROR: could not stop non-independent AdGuard Home"
      _engine_failed=1
    fi
  else
    _log "keeping AdGuard Home running: independent local-DNS engine is enabled"
  fi
  if [ "$(pg_get dns_forward 0 2>/dev/null)" != "1" ]; then
    if sh "$MP/scripts/unbound.sh" stop "$MP" "$PG" >> "$LOG" 2>&1; then
      rm -f "$EGRESS" || {
        _log "ERROR: Unbound stopped but its obsolete VPN egress marker could not be removed"
        _engine_failed=1
      }
    else
      _log "ERROR: could not stop non-independent Unbound; preserving VPN egress marker for recovery"
      _engine_failed=1
    fi
  else
    # Stage the previous binding so a failed unpin AND failed stop can restore
    # the marker. A later status/reconcile/stop then knows cleanup is incomplete.
    _egress_backup=""
    if [ -e "$EGRESS" ] || [ -L "$EGRESS" ]; then
      if [ ! -f "$EGRESS" ] || [ -L "$EGRESS" ]; then
        _log "ERROR: unsafe Unbound VPN egress marker; refusing to claim DNS cleanup"
        return 1
      fi
      _egress_backup=$(mktemp "$EGRESS.rollback.XXXXXX") || {
        _log "ERROR: unable to stage Unbound VPN egress marker for safe unpin"
        return 1
      }
      if [ ! -f "$_egress_backup" ] || [ -L "$_egress_backup" ] ||
          ! cat "$EGRESS" > "$_egress_backup" || ! chmod 600 "$_egress_backup"; then
        rm -f "$_egress_backup" 2>/dev/null || :
        _log "ERROR: unable to preserve previous Unbound VPN egress marker"
        return 1
      fi
      if ! rm -f "$EGRESS"; then
        rm -f "$_egress_backup" 2>/dev/null || :
        _log "ERROR: unable to clear Unbound VPN egress marker before reload"
        return 1
      fi
    fi
    if sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG" >> "$LOG" 2>&1; then
      [ -z "$_egress_backup" ] || rm -f "$_egress_backup" 2>/dev/null || :
      _log "refreshed independent Unbound without stale external-VPN egress binding"
      _log "keeping Unbound running: independent local-DNS forwarding is enabled"
    else
      _log "WARNING: independent Unbound refresh failed after VPN egress marker removal; stopping resolver to prevent stale egress"
      if sh "$MP/scripts/unbound.sh" stop "$MP" "$PG" >> "$LOG" 2>&1; then
        [ -z "$_egress_backup" ] || rm -f "$_egress_backup" 2>/dev/null || :
        _log "stopped Unbound after failed VPN-binding refresh; local DNS will recover on the next ensure"
      else
        if [ -n "$_egress_backup" ]; then
          if mv -f "$_egress_backup" "$EGRESS"; then
            _log "restored VPN egress marker because Unbound stop failed; cleanup remains retryable"
          else
            _log "ERROR: Unbound stop and egress marker restoration both failed"
          fi
        fi
        _log "ERROR: Unbound stop also failed; stale resolver process may remain and requires watchdog/manual recovery"
        _engine_failed=1
      fi
    fi
  fi
  [ "$_engine_failed" = 0 ]
}
_stop_locked() {
  if ! _clear_all; then
    # Keep local resolvers alive while any OUTPUT redirect may still target them.
    # Retained markers let the next status/reconcile/stop attempt retry cleanup.
    _log "ERROR: Root Proxy cleanup incomplete; DNS engines left running for safety"
    return 1
  fi
  if ! _stop_engines; then
    _log "ERROR: DNS engine shutdown/rebind could not be confirmed; cleanup remains retryable"
    return 1
  fi
  _log "stopped; removed only FX-owned DNS redirection chains"
}
_route_uses_if() {
  _route_text="$1"
  _expected_if="$2"
  _expected_src="$3"
  printf '%s\n' "$_route_text" | awk -v expected="$_expected_if" -v expected_src="$_expected_src" '
    {
      for (i=1; i<NF; i++) {
        if ($i == "dev") {dev_count++; actual_dev=$(i+1)}
        if ($i == "src") {src_count++; actual_src=$(i+1)}
      }
    }
    END {
      if (dev_count == 1 && actual_dev == expected &&
          src_count == 1 && actual_src == expected_src) exit 0
      exit 1
    }
  '
}
_resolve_vpn_egress() {
  _if="$1"
  _valid_if "$_if" || { _log "invalid tunnel interface"; return 1; }
  command -v ip >/dev/null 2>&1 || { _log "ip command missing"; return 1; }
  _link=$(ip -o link show dev "$_if" 2>/dev/null) || return 1
  printf '%s\n' "$_link" | grep -Eq '<[^>]*UP[^>]*>' || {
    _log "tunnel interface is not UP: $_if"; return 1;
  }
  _ip=$(ip -o -4 addr show dev "$_if" scope global 2>/dev/null \
        | awk '$3=="inet" {sub(/\/.*/,"",$4); print $4; exit}')
  [ -n "$_ip" ] && _valid_ipv4 "$_ip" || {
    _log "no valid global IPv4 address on tunnel: $_if"; return 1;
  }
  for _dest in 198.41.0.4 199.9.14.201 192.33.4.12 199.7.91.13 192.5.5.241 192.112.36.4; do
    _route=$(ip route get "$_dest" from "$_ip" 2>/dev/null) || {
      _log "route lookup failed through tunnel source $_ip for $_dest"; return 1;
    }
    _route_uses_if "$_route" "$_if" "$_ip" || {
      _log "route for $_dest from $_ip does not use $_if: $_route"; return 1;
    }
  done
  printf '%s\n' "$_ip"
}
_build_chain4() {
  _chain="$1"; _uid="$2"; _whitelist_uids="$3"
  iptables -t nat -N "$_chain" >/dev/null 2>&1 || iptables -t nat -F "$_chain" || return 1
  iptables -t nat -A "$_chain" -m owner --uid-owner 0 -j RETURN || return 1
  iptables -t nat -A "$_chain" -m owner --uid-owner "$_uid" -j RETURN || return 1
  while IFS= read -r _whitelist_uid; do
    [ -n "$_whitelist_uid" ] || continue
    _valid_uid "$_whitelist_uid" || return 1
    iptables -t nat -A "$_chain" -m owner --uid-owner "$_whitelist_uid" -j RETURN || return 1
  done <<EOF
$_whitelist_uids
EOF
  iptables -t nat -A "$_chain" -d 127.0.0.0/8 -j RETURN || return 1
  iptables -t nat -A "$_chain" -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:53 || return 1
  iptables -t nat -A "$_chain" -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:53 || return 1
}
_build_chain6() {
  _chain="$1"; _uid="$2"; _whitelist_uids="$3"
  ip6tables -t nat -N "$_chain" >/dev/null 2>&1 || ip6tables -t nat -F "$_chain" || return 1
  ip6tables -t nat -A "$_chain" -m owner --uid-owner 0 -j RETURN || return 1
  ip6tables -t nat -A "$_chain" -m owner --uid-owner "$_uid" -j RETURN || return 1
  while IFS= read -r _whitelist_uid; do
    [ -n "$_whitelist_uid" ] || continue
    _valid_uid "$_whitelist_uid" || return 1
    ip6tables -t nat -A "$_chain" -m owner --uid-owner "$_whitelist_uid" -j RETURN || return 1
  done <<EOF
$_whitelist_uids
EOF
  ip6tables -t nat -A "$_chain" -d ::1/128 -j RETURN || return 1
  ip6tables -t nat -A "$_chain" -p udp --dport 53 -j DNAT --to-destination '[::1]:53' || return 1
  ip6tables -t nat -A "$_chain" -p tcp --dport 53 -j DNAT --to-destination '[::1]:53' || return 1
}
_activate_chains() {
  _uid="$1"; _whitelist_uids="$2"
  _current=$(awk 'NR==1 {print $1}' "$ACTIVE" 2>/dev/null)
  case "$_current" in FXYRP4_A) _n4=FXYRP4_B; _o4=FXYRP4_A;; FXYRP4_B) _n4=FXYRP4_A; _o4=FXYRP4_B;; *) _n4=FXYRP4_A; _o4=FXYRP4_B;; esac
  case "$_current" in FXYRP4_A) _n6=FXYRP6_B; _o6=FXYRP6_A;; FXYRP4_B) _n6=FXYRP6_A; _o6=FXYRP6_B;; *) _n6=FXYRP6_A; _o6=FXYRP6_B;; esac
  _build_chain4 "$_n4" "$_uid" "$_whitelist_uids" || { _clear_chain iptables "$_n4"; _log "IPv4 DNS chain build failed"; return 1; }
  _build_chain6 "$_n6" "$_uid" "$_whitelist_uids" || {
    _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; _log "IPv6 NAT chain build failed"; return 1;
  }
  iptables -t nat -I OUTPUT 1 -j "$_n4" || { _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; return 1; }
  ip6tables -t nat -I OUTPUT 1 -j "$_n6" || {
    _remove_hook iptables "$_n4"; _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; return 1;
  }
  # Do not publish a new active generation while an older OUTPUT jump is
  # still attached. A stale chain can retain an obsolete VPN UID/whitelist and
  # redirect the newly active VPN's DNS packets into the local resolver.
  if ! _remove_hook iptables "$_o4" || ! _remove_hook ip6tables "$_o6"; then
    _remove_hook iptables "$_n4" || :
    _remove_hook ip6tables "$_n6" || :
    _clear_chain iptables "$_n4"
    _clear_chain ip6tables "$_n6"
    _log "unable to detach previous DNS redirect generation; refusing activation"
    return 1
  fi
  _clear_chain iptables "$_o4"
  _clear_chain ip6tables "$_o6"
  _active_tmp=$(mktemp "$ACTIVE.tmp.XXXXXX") || {
    _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; _log "unable to create active marker temp"; return 1;
  }
  if [ ! -f "$_active_tmp" ] || [ -L "$_active_tmp" ]; then
    rm -f "$_active_tmp" 2>/dev/null || :; _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; return 1;
  fi
  if ! { printf '%s\n%s\n' "$_n4" "$_n6" > "$_active_tmp" && chmod 600 "$_active_tmp" && mv -f "$_active_tmp" "$ACTIVE"; }; then
    rm -f "$_active_tmp" 2>/dev/null || :
    _clear_chain iptables "$_n4"
    _clear_chain ip6tables "$_n6"
    _log "failed to publish active chain marker; rolled back dual-stack DNS redirects (fail-open)"
    return 1
  fi
}
_ensure_locked() {
  _iface="$1"; _uid="$2"
  if ! _is_enabled; then
    if ! _stop_locked; then
      _log "disabled by settings, but Root Proxy cleanup is incomplete"
      return 1
    fi
    _log "disabled by settings or DNS forwarding off"
    return 0
  fi
  _valid_uid "$_uid" && _valid_if "$_iface" || {
    _stop_locked; _log "missing unique active VPN owner UID/interface; fail-open"; return 1;
  }
  _whitelist_uids=$(_resolve_whitelist_uids) || {
    _stop_locked
    _log "cannot resolve selected app DNS exceptions; fail-open"
    return 1
  }
  _egress=$(_resolve_vpn_egress "$_iface") || {
    _stop_locked; _log "VPN egress route could not be proven; fail-open"; return 1;
  }
  _egress_tmp=$(mktemp "$EGRESS.tmp.XXXXXX") || {
    _stop_locked
    _log "unable to create VPN egress marker temp; fail-open"
    return 1
  }
  if [ ! -f "$_egress_tmp" ] || [ -L "$_egress_tmp" ]; then
    rm -f "$_egress_tmp" 2>/dev/null || :
    _stop_locked
    _log "unsafe VPN egress marker temp; fail-open"
    return 1
  fi
  if ! {
    printf '%s\n' "$_egress" > "$_egress_tmp" &&
    chmod 600 "$_egress_tmp" &&
    mv -f "$_egress_tmp" "$EGRESS"
  }; then
    rm -f "$_egress_tmp" 2>/dev/null || :
    _stop_locked
    _log "failed to publish validated VPN egress marker; fail-open"
    return 1
  fi

  if ! sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG" >> "$LOG" 2>&1; then
    _stop_locked; _log "Unbound failed to bind through the external VPN; fail-open"; return 1;
  fi
  if ! sh "$MP/scripts/adguardhome.sh" ensure "$MP" "$PG" >> "$LOG" 2>&1; then
    _stop_locked; _log "AdGuard Home failed local DNS health checks; fail-open"; return 1;
  fi
  if ! _local_dns_probe; then
    _stop_locked; _log "post-start DNS probe failed; fail-open"; return 1;
  fi
  # DNS engines take time to start. Re-prove the VPN route and address after
  # their health probe, immediately before redirecting app DNS packets.
  _rechecked_egress=$(_resolve_vpn_egress "$_iface") || {
    _stop_locked
    _log "VPN egress could not be revalidated after DNS startup; fail-open"
    return 1
  }
  if [ "$_rechecked_egress" != "$_egress" ]; then
    _stop_locked
    _log "VPN egress changed during DNS startup ($_egress -> $_rechecked_egress); fail-open"
    return 1
  fi
  _activate_chains "$_uid" "$_whitelist_uids" || {
    _stop_locked; _log "dual-stack DNS NAT setup failed; fail-open"; return 1;
  }
  # Recheck after the redirect chains are live, immediately before committing
  # active state. This catches a tunnel address or route change during NAT setup.
  if ! _local_dns_probe; then
    _stop_locked
    _log "post-activation local DNS probe failed; fail-open"
    return 1
  fi
  _post_activation_egress=$(_resolve_vpn_egress "$_iface") || {
    _stop_locked
    _log "VPN egress route could not be revalidated after DNS redirects were activated; fail-open"
    return 1
  }
  if [ "$_post_activation_egress" != "$_egress" ]; then
    _stop_locked
    _log "VPN egress changed during DNS redirect activation ($_egress -> $_post_activation_egress); fail-open"
    return 1
  fi
  _meta_tmp=$(mktemp "$ACTIVE_META.tmp.XXXXXX") || {
    _stop_locked
    _log "unable to create Root Proxy active metadata temp; fail-open"
    return 1
  }
  if [ ! -f "$_meta_tmp" ] || [ -L "$_meta_tmp" ]; then
    rm -f "$_meta_tmp" 2>/dev/null || :
    _stop_locked
    _log "unsafe Root Proxy active metadata temp; fail-open"
    return 1
  fi
  if ! {
    printf '%s\n%s\n%s\n%s\n' "$_iface" "$_uid" "$_egress" "$(date '+%s')" > "$_meta_tmp" &&
    chmod 600 "$_meta_tmp" &&
    mv -f "$_meta_tmp" "$ACTIVE_META"
  }; then
    rm -f "$_meta_tmp" 2>/dev/null || :
    _stop_locked
    _log "failed to commit Root Proxy active state; rolled back DNS redirects (fail-open)"
    return 1
  fi
  _log "active: AdGuard DNS filtering is local; Unbound egress is pinned to $_egress on $_iface; VPN owner UID $_uid bypasses redirect"
  echo "active=1"
  echo "interface=$_iface"
  echo "vpn_uid=$_uid"
  echo "egress_ipv4=$_egress"
}
with_lock() {
  _lock_held=0
  _read_lock_owner() {
    _path=$1
    [ ! -L "$_path" ] || return 1
    if [ -d "$_path" ]; then
      # Never read a FIFO, device, or other special file as a legacy PID.
      # In particular, cat on a FIFO would block every DNS proxy operation.
      [ -f "$_path/pid" ] && [ ! -L "$_path/pid" ] || return 1
      cat "$_path/pid" 2>/dev/null
    elif [ -f "$_path" ]; then
      cat "$_path" 2>/dev/null
    else
      return 1
    fi
  }
  _remove_lock_path() {
    _path=$1
    [ ! -L "$_path" ] || return 1
    if [ -d "$_path" ]; then
      # Legacy lock directories contain at most one regular PID file. Never
      # recursively delete unknown contents from the private state directory.
      [ ! -L "$_path/pid" ] || return 1
      for _entry in "$_path"/* "$_path"/.[!.]* "$_path"/..?*; do
        [ -e "$_entry" ] || [ -L "$_entry" ] || continue
        [ "$_entry" = "$_path/pid" ] || return 1
      done
      if [ -e "$_path/pid" ]; then
        [ -f "$_path/pid" ] && [ ! -L "$_path/pid" ] || return 1
        rm -f "$_path/pid" 2>/dev/null || return 1
      fi
      rmdir "$_path" 2>/dev/null
    elif [ -f "$_path" ]; then
      rm -f "$_path" 2>/dev/null
    else
      return 1
    fi
  }
  _tries=0
  while :; do
    # The canonical lock is now a private regular file acquired with noclobber.
    # Directory/PID locks remain readable for safe migration from old releases.
    if [ ! -L "$LOCK" ] && [ ! -e "$LOCK" ]; then
      if ( umask 077; set -C; printf '%s\n' "$$" > "$LOCK" ) 2>/dev/null; then
        _lock_held=1
        break
      fi
    fi

    [ ! -L "$LOCK" ] || { echo "unsafe root DNS proxy lock symlink" >&2; return 11; }
    _owner="$(_read_lock_owner "$LOCK" 2>/dev/null || true)"
    case "$_owner" in
      ''|*[!0-9]*)
        # Reclaim only a legacy directory that stayed PID-less past the
        # publication grace period. Quarantine it with one atomic rename.
        if [ -d "$LOCK" ] && [ ! -L "$LOCK" ] && [ ! -e "$LOCK/pid" ] && [ "$_tries" -ge 10 ]; then
          _stale="$LOCK.stale.$$.$_tries"
          if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] && mv "$LOCK" "$_stale" 2>/dev/null; then
            _moved_owner="$(_read_lock_owner "$_stale" 2>/dev/null || true)"
            if [ -z "$_moved_owner" ] && [ ! -e "$_stale/pid" ]; then
              _remove_lock_path "$_stale" || :
            elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
              mv "$_stale" "$LOCK" 2>/dev/null || :
            fi
          fi
        fi
        ;;
      *)
        if ! kill -0 "$_owner" 2>/dev/null; then
          # Re-read before rename and validate the moved owner afterwards.
          # If another waiter has already replaced this lock, restore the
          # moved path instead of deleting a live operation's lock.
          _owner2="$(_read_lock_owner "$LOCK" 2>/dev/null || true)"
          if [ "$_owner2" = "$_owner" ] && ! kill -0 "$_owner2" 2>/dev/null; then
            _stale="$LOCK.stale.$$.$_tries"
            if [ ! -e "$_stale" ] && [ ! -L "$_stale" ] && mv "$LOCK" "$_stale" 2>/dev/null; then
              _moved_owner="$(_read_lock_owner "$_stale" 2>/dev/null || true)"
              if [ "$_moved_owner" = "$_owner" ] && ! kill -0 "$_moved_owner" 2>/dev/null; then
                _remove_lock_path "$_stale" || :
              elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
                mv "$_stale" "$LOCK" 2>/dev/null || :
              fi
            fi
          fi
        fi
        ;;
    esac

    _tries=$((_tries+1))
    [ "$_tries" -lt 20 ] || { echo "root DNS proxy update is busy" >&2; return 10; }
    sleep 1
  done

  cleanup_lock() {
    [ -z "$_RPROXY_TEMP" ] || rm -f "$_RPROXY_TEMP" 2>/dev/null || :
    [ "$_lock_held" = 1 ] || return 0
    _owner="$(_read_lock_owner "$LOCK" 2>/dev/null || true)"
    if [ "$_owner" = "$$" ]; then
      _release="$LOCK.release.$$"
      _release_try=0
      while { [ -e "$_release" ] || [ -L "$_release" ]; } && [ "$_release_try" -lt 20 ]; do
        _release_try=$((_release_try+1))
        _release="$LOCK.release.$$.$_release_try"
      done
      if [ ! -e "$_release" ] && [ ! -L "$_release" ] && mv "$LOCK" "$_release" 2>/dev/null; then
        _release_owner="$(_read_lock_owner "$_release" 2>/dev/null || true)"
        if [ "$_release_owner" = "$$" ]; then
          _remove_lock_path "$_release" || :
        elif [ ! -e "$LOCK" ] && [ ! -L "$LOCK" ]; then
          mv "$_release" "$LOCK" 2>/dev/null || :
        fi
      fi
    fi
    _lock_held=0
    return 0
  }
  # Signal handlers exit first; EXIT performs the one authoritative cleanup.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
}
_whitelist_set_locked() {
  _package="$1"; _state="$2"
  _whitelist_set_value "$_package" "$_state" || return $?
  echo "saved=1"
  if [ -s "$ACTIVE_META" ]; then
    [ ! -L "$ACTIVE_META" ] || { _stop_locked; _log "unsafe active metadata symlink; fail-open"; return 1; }
    _iface=$(sed -n '1p' "$ACTIVE_META" 2>/dev/null)
    _uid=$(sed -n '2p' "$ACTIVE_META" 2>/dev/null)
    _valid_if "$_iface" && _valid_uid "$_uid" || { _stop_locked; _log "invalid active metadata after whitelist update"; return 1; }
    _ensure_locked "$_iface" "$_uid"
  else
    echo "active=0"
  fi
}
_status_fail_open() {
  _reason=$1
  # Status runs under the Root Proxy lock. Reconcile every failed proof to a
  # clean fail-open state, removing only FX-owned NAT chains and markers.
  # _stop_engines preserves Unbound/AdGuard when independently enabled.
  if ! _stop_locked; then
    echo "active=0"
    echo "reason=$_reason"
    echo "cleanup=failed"
    return 1
  fi
  echo "active=0"
  echo "reason=$_reason"
}
_status_locked() {
  echo "enabled=$(pg_get vpn_external_dns_proxy 1)"
  echo "dns_forward=$(pg_get dns_forward 1)"
  echo "whitelist_count=$(printf '%s\n' "$(_list_whitelist_packages)" | awk 'NF {n++} END {print n+0}')"

  # Never disable or overwrite Android Private DNS. Strict DoT can bypass
  # port-53 filtering; expose actual coverage instead of claiming full
  # ad filtering while Android is using a pinned encrypted resolver.
  _private_dns_mode=$(settings get global private_dns_mode 2>/dev/null || printf unknown)
  case "$_private_dns_mode" in off|opportunistic|hostname) : ;; *) _private_dns_mode=unknown ;; esac
  echo "private_dns_mode=$_private_dns_mode"
  case "$_private_dns_mode" in
    off) echo "dns_filter_coverage=port53_redirect_active" ;;
    opportunistic) echo "dns_filter_coverage=opportunistic_private_dns_may_bypass_redirect" ;;
    hostname) echo "dns_filter_coverage=strict_private_dns_bypasses_redirect" ;;
    *) echo "dns_filter_coverage=unknown" ;;
  esac
  if ! _is_enabled; then
    _status_fail_open disabled; return $?
  fi
  if [ ! -e "$ACTIVE_META" ] && [ ! -e "$ACTIVE" ] && [ ! -e "$EGRESS" ]; then
    _status_fail_open not_active; return $?
  fi
  for _state_file in "$ACTIVE_META" "$ACTIVE" "$EGRESS"; do
    [ -f "$_state_file" ] && [ ! -L "$_state_file" ] || {
      _status_fail_open invalid_or_missing_state; return $?
    }
  done
  _iface=$(sed -n '1p' "$ACTIVE_META" 2>/dev/null || :)
  _uid=$(sed -n '2p' "$ACTIVE_META" 2>/dev/null || :)
  _meta_egress=$(sed -n '3p' "$ACTIVE_META" 2>/dev/null || :)
  _activated_at=$(sed -n '4p' "$ACTIVE_META" 2>/dev/null || :)
  _active4=$(sed -n '1p' "$ACTIVE" 2>/dev/null || :)
  _active6=$(sed -n '2p' "$ACTIVE" 2>/dev/null || :)
  case "$_active4" in FXYRP4_A|FXYRP4_B) : ;; *) _status_fail_open invalid_ipv4_chain; return $? ;; esac
  case "$_active6" in FXYRP6_A|FXYRP6_B) : ;; *) _status_fail_open invalid_ipv6_chain; return $? ;; esac
  _valid_if "$_iface" && _valid_uid "$_uid" && _valid_ipv4 "$_meta_egress" || {
    _status_fail_open invalid_active_metadata; return $?
  }
  _stored_egress=$(tr -d '\r\n' < "$EGRESS" 2>/dev/null || :)
  if [ "$_stored_egress" != "$_meta_egress" ]; then
    _status_fail_open egress_marker_mismatch; return $?
  fi
  _current_egress=$(_resolve_vpn_egress "$_iface" 2>/dev/null) || {
    _status_fail_open vpn_route_unavailable; return $?
  }
  if [ "$_current_egress" != "$_meta_egress" ]; then
    _status_fail_open vpn_egress_changed; return $?
  fi
  if ! iptables -t nat -C OUTPUT -j "$_active4" >/dev/null 2>&1; then
    _status_fail_open ipv4_redirect_missing; return $?
  fi
  if ! ip6tables -t nat -C OUTPUT -j "$_active6" >/dev/null 2>&1; then
    _status_fail_open ipv6_redirect_missing; return $?
  fi
  if ! _local_dns_probe; then
    _status_fail_open local_dns_probe_failed; return $?
  fi
  echo "interface=$_iface"
  echo "vpn_uid=$_uid"
  echo "egress_ipv4=$_meta_egress"
  echo "activated_at=$_activated_at"
  echo "redirects=attached"
  echo "route=verified"
  echo "dns_probe=passed"
  echo "active=1"
}
_reconcile_locked() {
  if [ ! -e "$ACTIVE_META" ]; then
    # A crash can occur after NAT hooks/markers are published but before the
    # authoritative metadata rename. Never leave those redirects attached
    # without metadata that proves the owning VPN interface and UID.
    if [ -e "$ACTIVE" ] || [ -e "$EGRESS" ] \
        || iptables -t nat -C OUTPUT -j FXYRP4_A >/dev/null 2>&1 \
        || iptables -t nat -C OUTPUT -j FXYRP4_B >/dev/null 2>&1 \
        || ip6tables -t nat -C OUTPUT -j FXYRP6_A >/dev/null 2>&1 \
        || ip6tables -t nat -C OUTPUT -j FXYRP6_B >/dev/null 2>&1; then
      _log "active metadata missing while FX-owned DNS redirect state remains; fail-open cleanup"
      if ! _stop_locked; then
        echo "active=0"
        echo "cleanup=failed"
        return 1
      fi
    fi
    echo "active=0"
    return 0
  fi
  [ -f "$ACTIVE_META" ] && [ ! -L "$ACTIVE_META" ] || { _stop_locked; _log "unsafe active metadata during package event"; return 1; }
  _iface=$(sed -n '1p' "$ACTIVE_META" 2>/dev/null)
  _uid=$(sed -n '2p' "$ACTIVE_META" 2>/dev/null)
  _valid_if "$_iface" && _valid_uid "$_uid" || { _stop_locked; _log "invalid active metadata during package event"; return 1; }
  _ensure_locked "$_iface" "$_uid"
}
cmd=${1:-status}
case "$cmd" in
  ensure)
    [ "$#" -ge 5 ] || { echo "usage: $0 ensure module data_dir interface vpn_uid" >&2; exit 2; }
    MP="$2"; PG="$3"; CONF="$PG/settings.conf"; shift 3
    with_lock _ensure_locked "$1" "$2"
    ;;
  stop)
    with_lock _stop_locked
    ;;
  enable|disable)
    [ -f "$CONF" ] || { echo "settings file missing" >&2; exit 21; }
    if [ "$cmd" = enable ]; then pg_set vpn_external_dns_proxy 1; else pg_set vpn_external_dns_proxy 0; fi
    sh "$MP/scripts/apply.sh" fast
    ;;
  status)
    with_lock _status_locked
    ;;
  whitelist-list)
    echo "FXYRPWHITELIST1"
    _list_whitelist_packages | while IFS= read -r _package; do
      [ -n "$_package" ] && printf 'PACKAGE|%s\n' "$_package"
    done
    ;;
  whitelist-set)
    [ "$#" -eq 3 ] && _valid_package "$2" && { [ "$3" = 0 ] || [ "$3" = 1 ]; } \
      || { echo "usage: yulong-root-proxy.sh whitelist-set PACKAGE 0|1" >&2; exit 2; }
    with_lock _whitelist_set_locked "$2" "$3"
    ;;
  reconcile)
    with_lock _reconcile_locked
    ;;
  uninstall)
    with_lock _stop_locked
    ;;
  *) echo 'usage: yulong-root-proxy.sh {ensure|stop|enable|disable|status|whitelist-list|whitelist-set|reconcile|uninstall}' >&2; exit 64 ;;
esac
