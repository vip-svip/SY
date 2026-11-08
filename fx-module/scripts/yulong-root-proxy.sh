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
PROBE="$MP/engines/unbound/fx-dns-probe"
LOCK="$PG/yulong-root-proxy.lock"
LOG="$PG/yulong-root-proxy.log"
_RPROXY_TEMP=
_RPROXY_PRUNE_PACKAGES=
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
  [ -f "$PROBE" ] && [ -x "$PROBE" ] && [ ! -L "$PROBE" ] || return 1
  "$PROBE" "$_server" 53 5 udp >> "$LOG" 2>&1 || return 1
  "$PROBE" "$_server" 53 5 tcp >> "$LOG" 2>&1
}
_local_dns_probe() {
  # Require both loopback families to answer over UDP and TCP before either
  # FX-owned OUTPUT redirect chain is attached.
  _local_dns_probe_endpoint 127.0.0.1 || return 1
  _local_dns_probe_endpoint ::1 || return 1
}
_is_enabled() {
  # Root Proxy redirects port 53 to the FX-owned AdGuard Home listener.
  # Do not arm the redirect when either AdGuard or its sole local Unbound
  # upstream is disabled; otherwise DNS could hit an unrelated local service.
  [ "$(pg_get vpn_external_dns_proxy 1 2>/dev/null)" = "1" ] \
    && [ "$(pg_get vpn_external_compat 1 2>/dev/null)" = "1" ] \
    && [ "$(pg_get dns_engine_adguardhome 0 2>/dev/null)" = "1" ] \
    && [ "$(pg_get dns_forward 1 2>/dev/null)" = "1" ]
}
_valid_package() {
  case "${1:-}" in ''|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$'
}
_list_whitelist_packages() {
  [ -f "$CONF" ] && [ ! -L "$CONF" ] && [ -r "$CONF" ] || return 1
  # Treat the whitelist as one atomic policy document. Never silently discard
  # malformed or duplicate entries: doing so can apply a different UID set
  # from the one the user sees in the settings UI.
  awk -F'|' '
    BEGIN {inside=0; sections=0; count=0; invalid=0}
    {
      sub(/\r$/, "")
      if($0=="[list:yulong_root_proxy_whitelist]") {
        sections++
        if(sections>1) invalid=1
        inside=1
        next
      }
      if(/^\[/) {inside=0; next}
      if(!inside || $0=="" || $0 ~ /^[ \t]*#/) next
      if(NF!=2 || $1 !~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ ||
          ($2!="0" && $2!="1")) {invalid=1; next}
      if($1 in seen) {invalid=1; next}
      seen[$1]=1
      if($2=="1") enabled[++count]=$1
    }
    END {
      if(sections!=1 || invalid) exit 2
      for(i=1;i<=count;i++) print enabled[i]
    }
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

  # Resolve all selected packages against one in-memory PackageManager pass.
  # The previous implementation launched one AWK process and rescanned the
  # full package snapshot for every whitelist entry.
  _resolved=$( {
    printf '%s\n' "$_packages"
    printf '%s\n' "__FX_ROOT_PROXY_UID_SNAPSHOT__"
    printf '%s\n' "$_snapshot"
  } | awk '
    $0=="__FX_ROOT_PROXY_UID_SNAPSHOT__" {phase=1; next}
    !phase {
      if($0 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/) wanted[$0]=1
      next
    }
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      sub(/[ \t]+$/, "", line)
      n=split(line, field, /[ \t]+/)
      if(field[1] ~ /^package:[A-Za-z0-9_.-]+$/) {
        for(j=2;j<=n;j++) if(field[j] ~ /^uid:[0-9]+$/) {snapshot_valid=1; break}
        package=substr(field[1],9)
        if(package in wanted) {
          uid=""
          for(i=2;i<=n;i++) if(field[i] ~ /^uid:[0-9]+$/) {
            uid=substr(field[i],5)
            break
          }
          # Match legacy behavior: a selected package missing from a partial
          # PackageManager row contributes no UID; malformed explicit UIDs fail.
          if(uid!="") {
            if(uid !~ /^[0-9]+$/ || uid=="0") invalid=1
            else if(!(uid in seen_uid)) {
              seen_uid[uid]=1
              ordered[++count]=uid
            }
          }
        }
      }
    }
    END {
      if(!snapshot_valid || invalid) exit 1
      for(i=1;i<=count;i++) print ordered[i]
    }
  ' ) || {
    _log "PackageManager UID snapshot is malformed or contains an invalid selected UID; fail-open"
    return 1
  }
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
  # Android VPN interfaces may expose more than one global IPv4 address.
  # Do not assume the first address is the one selected by policy routing:
  # test each candidate as an explicit source and publish only one that
  # consistently resolves every authoritative destination through this TUN.
  _addresses=$(ip -o -4 addr show dev "$_if" scope global 2>/dev/null \
        | awk '$3=="inet" {sub(/\/.*/,"",$4); print $4}')
  [ -n "$_addresses" ] || {
    _log "no global IPv4 address on tunnel: $_if"; return 1;
  }
  for _ip in $_addresses; do
    _valid_ipv4 "$_ip" || continue
    _route_ok=1
    for _dest in 198.41.0.4 199.9.14.201 192.33.4.12 199.7.91.13 192.5.5.241 192.112.36.4; do
      _route=$(ip route get "$_dest" from "$_ip" 2>/dev/null) || {
        _log "route lookup failed through tunnel source $_ip for $_dest"
        _route_ok=0
        break
      }
      if ! _route_uses_if "$_route" "$_if" "$_ip"; then
        _log "route for $_dest from $_ip does not use $_if: $_route"
        _route_ok=0
        break
      fi
    done
    if [ "$_route_ok" = 1 ]; then
      printf '%s\n' "$_ip"
      return 0
    fi
  done
  _log "no global IPv4 source on $_if passed all authoritative route checks"
  return 1
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
  # A crash can leave an OUTPUT jump to the would-be next generation while
  # its ACTIVE marker is missing/stale. Detach that candidate before -N/-F:
  # flushing a chain that OUTPUT still references exposes a partially rebuilt
  # DNS policy to live traffic. Never begin rebuilding until both families are
  # positively detached from their candidate generations.
  if ! _remove_hook iptables "$_n4" || ! _remove_hook ip6tables "$_n6"; then
    _log "unable to detach candidate DNS generation before rebuild; refusing activation"
    return 1
  fi
  _build_chain4 "$_n4" "$_uid" "$_whitelist_uids" || { _clear_chain iptables "$_n4"; _log "IPv4 DNS chain build failed"; return 1; }
  _build_chain6 "$_n6" "$_uid" "$_whitelist_uids" || {
    _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; _log "IPv6 NAT chain build failed"; return 1;
  }
  # Validate the full ordered rule sets while both candidate chains are still
  # detached. If the kernel accepted only a partial/altered sequence, discard
  # the candidates before any app packet can enter either generation.
  if ! _root_proxy_chain_contract 4 "$_n4" "$_uid" "$_whitelist_uids" || \
     ! _root_proxy_chain_contract 6 "$_n6" "$_uid" "$_whitelist_uids"; then
    _clear_chain iptables "$_n4"
    _clear_chain ip6tables "$_n6"
    _log "exact dual-stack DNS chain contract check failed before OUTPUT attachment"
    return 1
  fi
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
  # Root Proxy can prove Unbound's egress through the external VPN, but it
  # cannot prove that AdGuard's separate custom/global/fallback/bootstrap
  # sockets use that same tunnel. Require every AdGuard DNS upstream path to
  # be the VPN-bound local Unbound listener before attaching app DNS redirects.
  if ! _adguard_upstreams_use_vpn_bound_unbound; then
    _stop_locked
    _log "AdGuard Home has a custom/global or non-local fallback/bootstrap upstream; refusing Root Proxy activation because its external-VPN egress is unproven (fail-open)"
    return 1
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
  # The AdGuard config is a separate atomic file from Root Proxy's firewall
  # transaction. Re-read it after both OUTPUT hooks are installed and before
  # active metadata is committed, so a concurrent config replacement cannot
  # turn an initially safe local-Unbound chain into an unpinned upstream route.
  if ! _adguard_upstreams_use_vpn_bound_unbound; then
    _stop_locked
    _log "AdGuard upstream route changed during DNS redirect activation; rolled back both OUTPUT hooks (fail-open)"
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
  # Close the final config-writer race: an AdGuard lifecycle update may replace
  # its YAML while ACTIVE_META is being atomically published. Recheck after
  # the commit too; on drift, remove the just-published state and both hooks.
  if ! _adguard_upstreams_use_vpn_bound_unbound; then
    _stop_locked
    _log "AdGuard upstream route changed while committing Root Proxy active metadata; rolled back both OUTPUT hooks (fail-open)"
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
    [ -z "$_RPROXY_PRUNE_PACKAGES" ] || rm -f "$_RPROXY_PRUNE_PACKAGES" 2>/dev/null || :
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
_whitelist_prune_locked() {
  _prune_reconcile=${1:-1}
  case "$_prune_reconcile" in 0|1) ;; *) return 2 ;; esac
  [ -f "$CONF" ] && [ ! -L "$CONF" ] || { _log "settings.conf is missing or unsafe"; return 21; }
  _snapshot=$(cmd package list packages -U 2>/dev/null) || { _log "cannot read PackageManager snapshot; whitelist unchanged"; return 1; }
  [ -n "$_snapshot" ] || { _log "PackageManager returned an empty snapshot; whitelist unchanged"; return 1; }

  # Materialize a validated installed-package set once. The previous loop
  # rewrote settings.conf once per stale package, which made large inventories
  # needlessly slow and exposed many separate write windows.
  _RPROXY_PRUNE_PACKAGES=$(mktemp "$PG/yulong-root-proxy-packages.XXXXXX") || return 1
  if ! printf '%s\n' "$_snapshot" | awk '
    $1 ~ /^package:[A-Za-z0-9_.-]+$/ {
      pkg=substr($1,9); uid_ok=0
      for(i=2;i<=NF;i++) if($i ~ /^uid:[0-9]+$/) {uid_ok=1; break}
      if(uid_ok && pkg ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/) {
        if(!seen[pkg]++) print pkg
        valid++
      }
    }
    END {exit !valid}
  ' > "$_RPROXY_PRUNE_PACKAGES"; then
    rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
    _log "PackageManager snapshot is malformed; whitelist unchanged"
    return 1
  fi
  [ -s "$_RPROXY_PRUNE_PACKAGES" ] || {
    rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
    _log "PackageManager snapshot has no usable package/UID rows; whitelist unchanged"
    return 1
  }
  chmod 600 "$_RPROXY_PRUNE_PACKAGES" 2>/dev/null || {
    rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
    return 1
  }

  _removed=$(awk -F'|' '
    FNR==NR {installed[$1]=1; next}
    $0=="[list:yulong_root_proxy_whitelist]" {inside=1; next}
    /^\[/ {inside=0}
    inside && $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ && $2=="1" && !($1 in installed) {
      count++
    }
    END {print count+0}
  ' "$_RPROXY_PRUNE_PACKAGES" "$CONF") || {
    rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
    return 1
  }
  case "$_removed" in ''|*[!0-9]*)
    rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
    _log "unable to count stale DNS whitelist entries; whitelist unchanged"
    return 1
    ;;
  esac

  if [ "$_removed" -gt 0 ]; then
    [ -f "$CONF" ] && [ ! -L "$CONF" ] || {
      rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
      _log "settings.conf changed to an unsafe path during whitelist prune"
      return 21
    }
    _RPROXY_TEMP=$(mktemp "$CONF.yulong-rootproxy-prune.XXXXXX") || {
      rm -f "$_RPROXY_PRUNE_PACKAGES"; _RPROXY_PRUNE_PACKAGES=
      return 1
    }
    if ! awk -F'|' '
      FNR==NR {installed[$1]=1; next}
      $0=="[list:yulong_root_proxy_whitelist]" {inside=1; print; next}
      /^\[/ {inside=0}
      inside && $1 ~ /^[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+$/ && $2=="1" && !($1 in installed) {next}
      {print}
    ' "$_RPROXY_PRUNE_PACKAGES" "$CONF" > "$_RPROXY_TEMP"; then
      rm -f "$_RPROXY_TEMP" "$_RPROXY_PRUNE_PACKAGES"
      _RPROXY_TEMP=; _RPROXY_PRUNE_PACKAGES=
      _log "unable to stage atomic DNS whitelist prune; configuration unchanged"
      return 1
    fi
    if [ -s "$_RPROXY_TEMP" ] && [ -f "$_RPROXY_TEMP" ] && [ ! -L "$_RPROXY_TEMP" ] \
        && [ -f "$CONF" ] && [ ! -L "$CONF" ] \
        && chmod 600 "$_RPROXY_TEMP" && mv -f "$_RPROXY_TEMP" "$CONF"; then
      _RPROXY_TEMP=
    else
      rm -f "$_RPROXY_TEMP" "$_RPROXY_PRUNE_PACKAGES"
      _RPROXY_TEMP=; _RPROXY_PRUNE_PACKAGES=
      _log "atomic DNS whitelist prune commit failed; configuration unchanged"
      return 1
    fi
  fi
  rm -f "$_RPROXY_PRUNE_PACKAGES"
  _RPROXY_PRUNE_PACKAGES=
  echo "removed=$_removed"

  if [ "$_removed" -gt 0 ] && [ "$_prune_reconcile" = 1 ] && [ -s "$ACTIVE_META" ]; then
    [ ! -L "$ACTIVE_META" ] || { _stop_locked; _log "unsafe active metadata after whitelist prune"; return 1; }
    _iface=$(sed -n '1p' "$ACTIVE_META" 2>/dev/null)
    _uid=$(sed -n '2p' "$ACTIVE_META" 2>/dev/null)
    _valid_if "$_iface" && _valid_uid "$_uid" || { _stop_locked; _log "invalid active metadata after whitelist prune"; return 1; }
    _ensure_locked "$_iface" "$_uid" || return $?
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
  case "$_reason" in
    adguard_upstream_unpinned) echo "adguard_upstream_route=unverified" ;;
    *) echo "adguard_upstream_route=unknown" ;;
  esac
  echo "cleanup=complete"
}
_status_locked() {
  echo "enabled=$(pg_get vpn_external_dns_proxy 1)"
  echo "dns_forward=$(pg_get dns_forward 1)"
  echo "dns_engine_adguardhome=$(pg_get dns_engine_adguardhome 0)"
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
  if ! _adguard_upstreams_use_vpn_bound_unbound; then
    _status_fail_open adguard_upstream_unpinned; return $?
  fi
  echo "interface=$_iface"
  echo "vpn_uid=$_uid"
  echo "egress_ipv4=$_meta_egress"
  echo "activated_at=$_activated_at"
  echo "redirects=attached"
  echo "route=verified"
  echo "dns_probe=passed"
  echo "adguard_upstream_route=unbound_pinned"
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
# AdGuard Home can send explicitly configured custom/global upstreams and
# fallback servers directly, bypassing the VPN-bound Unbound process. Root
# Proxy may still redirect client port-53 packets to AdGuard, but that is not
# proof the resolver's outbound sockets use the same validated VPN egress.
_adguard_upstreams_use_vpn_bound_unbound() {
  _custom_dns_flag=$(pg_get custom_dns 0 2>/dev/null) || return 1
  _global_dns_flag=$(pg_get global_dns 0 2>/dev/null) || return 1
  [ "$_custom_dns_flag" = 0 ] && [ "$_global_dns_flag" = 0 ] || return 1
  _adguard_cfg="$PG/adguardhome/AdGuardHome.yaml"
  _reject_symlink_components "$_adguard_cfg" || return 1
  [ -f "$_adguard_cfg" ] && [ ! -L "$_adguard_cfg" ] && [ -r "$_adguard_cfg" ] || return 1
  awk '
    /^dns:[[:space:]]*$/ {dns_sections++; inside=1; section=""; next}
    inside && /^[^[:space:]]/ {inside=0; section=""}
    inside && /^  upstream_dns_file:/ {
      upstream_file_sections++
      value=$0; sub(/^  upstream_dns_file:[[:space:]]*/,"",value)
      if (value!="\"\"") unsafe=1
      section=""; next
    }
    inside && /^  use_private_ptr_resolvers:/ {
      private_ptr_sections++
      value=$0; sub(/^  use_private_ptr_resolvers:[[:space:]]*/,"",value)
      if (value!="false") unsafe=1
      section=""; next
    }
    inside && /^  local_ptr_upstreams:/ {
      local_ptr_sections++
      rest=$0; sub(/^  local_ptr_upstreams:/,"",rest)
      if (rest !~ /^[[:space:]]*\[\][[:space:]]*$/) unsafe=1
      section=""; next
    }
    inside && /^  upstream_dns:[[:space:]]*$/ {
      upstream_sections++; section="upstream"; next
    }
    inside && /^  fallback_dns:/ {
      fallback_sections++
      rest=$0; sub(/^  fallback_dns:/,"",rest)
      if (rest ~ /^[[:space:]]*\[\][[:space:]]*$/) {section=""; next}
      if (rest !~ /^[[:space:]]*$/) {unsafe=1; section=""; next}
      section="fallback"; next
    }
    inside && /^  bootstrap_dns:/ {
      bootstrap_sections++
      rest=$0; sub(/^  bootstrap_dns:/,"",rest)
      if (rest ~ /^[[:space:]]*\[\][[:space:]]*$/) {section=""; next}
      if (rest !~ /^[[:space:]]*$/) {unsafe=1; section=""; next}
      section="bootstrap"; next
    }
    inside && /^  [A-Za-z_][A-Za-z0-9_-]*:/ {section=""; next}
    inside && section!="" && /^[[:space:]]*#/ {next}
    inside && section!="" && /^[[:space:]]+- / {
      if ($0 !~ /^  - /) {unsafe=1; next}
      server=substr($0,5)
      sub(/^"/,"",server); sub(/"$/,"",server)
      counts[section]++
      if(server!="127.0.0.1:5353") unsafe=1
      else local_counts[section]++
      next
    }
    inside && section!="" && /^[[:space:]]/ {unsafe=1; section=""; next}
    END {
      if(dns_sections!=1 || upstream_sections!=1 ||
         upstream_file_sections!=1 || private_ptr_sections!=1 ||
         local_ptr_sections!=1 || counts["upstream"]!=1 ||
         local_counts["upstream"]!=1 ||
         fallback_sections>1 || bootstrap_sections>1 || unsafe ||
         counts["fallback"]!=local_counts["fallback"] ||
         counts["bootstrap"]!=local_counts["bootstrap"]) exit 1
      exit 0
    }
  ' "$_adguard_cfg"
}

_root_proxy_chain_contract() {
  _family=$1; _chain=$2; _uid=$3; _whitelist_uids=$4
  if [ "$_family" = 4 ]; then
    _bin=iptables; _loopback=127.0.0.0/8
    _udp_destination=127.0.0.1:53; _tcp_destination=127.0.0.1:53
  else
    _bin=ip6tables; _loopback=::1/128
    _udp_destination='[::1]:53'; _tcp_destination='[::1]:53'
  fi
  _valid_uid "$_uid" || return 1

  # Presence-only -C checks are insufficient: an earlier broad rule can
  # shadow the whitelist/loopback exceptions, and an extra DNAT can capture
  # packets before the intended policy. Enumerate the entire owned chain and
  # require the exact ordered rule set that _build_chain{4,6} publishes.
  _actual=$("$_bin" -t nat -S "$_chain" 2>/dev/null) || return 1
  _actual_rules=$(printf '%s\n' "$_actual" | awk -v chain="$_chain" '
    $1=="-N" && $2==chain {next}
    $1=="-A" && $2==chain {print; count++; next}
    {bad=1}
    END {if (bad || count==0) exit 1}
  ') || return 1
  _expected_rules=$(
    printf '%s\n' \
      "-A $_chain -m owner --uid-owner 0 -j RETURN" \
      "-A $_chain -m owner --uid-owner $_uid -j RETURN"
    while IFS= read -r _whitelist_uid; do
      [ -n "$_whitelist_uid" ] || continue
      _valid_uid "$_whitelist_uid" || exit 1
      printf '%s\n' "-A $_chain -m owner --uid-owner $_whitelist_uid -j RETURN"
    done <<EOF_ROOT_PROXY_UIDS
$_whitelist_uids
EOF_ROOT_PROXY_UIDS
    printf '%s\n' \
      "-A $_chain -d $_loopback -j RETURN" \
      "-A $_chain -p udp --dport 53 -j DNAT --to-destination $_udp_destination" \
      "-A $_chain -p tcp --dport 53 -j DNAT --to-destination $_tcp_destination"
  ) || return 1
  [ "$_actual_rules" = "$_expected_rules" ]
}

# Read-only Root Proxy proof used by the VPN coexistence arbiter.
# Unlike "status", this command never invokes _stop_locked or repairs rules:
# a diagnostic must not change a user's active network path. It validates the
# committed VPN identity/egress, current source-specific routes to the
# authoritative resolver probes, both OUTPUT jumps, the complete owned chain
# contracts and the live dual-stack DNS health probe.
_observe_locked() {
  _observe_fail() {
    echo "active=0"
    echo "dns_chain=unverified"
    echo "reason=$1"
    return 1
  }
  _is_enabled || { _observe_fail disabled; return 1; }
  for _state_file in "$ACTIVE_META" "$ACTIVE" "$EGRESS"; do
    [ -f "$_state_file" ] && [ ! -L "$_state_file" ] || {
      _observe_fail invalid_or_missing_state; return 1;
    }
  done
  _iface=$(sed -n '1p' "$ACTIVE_META" 2>/dev/null || :)
  _uid=$(sed -n '2p' "$ACTIVE_META" 2>/dev/null || :)
  _meta_egress=$(sed -n '3p' "$ACTIVE_META" 2>/dev/null || :)
  _active4=$(sed -n '1p' "$ACTIVE" 2>/dev/null || :)
  _active6=$(sed -n '2p' "$ACTIVE" 2>/dev/null || :)
  case "$_active4" in FXYRP4_A|FXYRP4_B) : ;; *) _observe_fail invalid_ipv4_chain; return 1 ;; esac
  case "$_active6" in FXYRP6_A|FXYRP6_B) : ;; *) _observe_fail invalid_ipv6_chain; return 1 ;; esac
  _valid_if "$_iface" && _valid_uid "$_uid" && _valid_ipv4 "$_meta_egress" || {
    _observe_fail invalid_active_metadata; return 1;
  }
  _stored_egress=$(tr -d '\r\n' < "$EGRESS" 2>/dev/null || :)
  [ "$_stored_egress" = "$_meta_egress" ] || {
    _observe_fail egress_marker_mismatch; return 1;
  }
  _current_egress=$(_resolve_vpn_egress "$_iface" 2>/dev/null) || {
    _observe_fail vpn_route_unavailable; return 1;
  }
  [ "$_current_egress" = "$_meta_egress" ] || {
    _observe_fail vpn_egress_changed; return 1;
  }
  iptables -t nat -C OUTPUT -j "$_active4" >/dev/null 2>&1 || {
    _observe_fail ipv4_redirect_missing; return 1;
  }
  ip6tables -t nat -C OUTPUT -j "$_active6" >/dev/null 2>&1 || {
    _observe_fail ipv6_redirect_missing; return 1;
  }
  _whitelist_uids=$(_resolve_whitelist_uids 2>/dev/null) || {
    _observe_fail whitelist_uid_snapshot_unavailable; return 1;
  }
  _root_proxy_chain_contract 4 "$_active4" "$_uid" "$_whitelist_uids" || {
    _observe_fail ipv4_chain_contract_mismatch; return 1;
  }
  _root_proxy_chain_contract 6 "$_active6" "$_uid" "$_whitelist_uids" || {
    _observe_fail ipv6_chain_contract_mismatch; return 1;
  }
  _local_dns_probe || {
    _observe_fail local_dns_probe_failed; return 1;
  }
  _private_dns_mode=$(settings get global private_dns_mode 2>/dev/null || printf unknown)
  case "$_private_dns_mode" in off|opportunistic|hostname) : ;; *) _private_dns_mode=unknown ;; esac
  case "$_private_dns_mode" in
    off) _coverage=port53_redirect_active; _dns_chain=verified ;;
    opportunistic) _coverage=opportunistic_private_dns_may_bypass_redirect; _dns_chain=partial ;;
    hostname) _coverage=strict_private_dns_bypasses_redirect; _dns_chain=partial ;;
    *) _coverage=unknown; _dns_chain=unverified ;;
  esac
  _adguard_upstream_route=unverified
  if _adguard_upstreams_use_vpn_bound_unbound; then
    _adguard_upstream_route=unbound_pinned
  fi
  # Port-53 interception and a successful Unbound probe do not prove that
  # AdGuard's primary/fallback upstream sockets use Unbound. Custom/global
  # upstreams are direct AdGuard sockets and remain unverified against the
  # third-party VPN's per-app routing policy.
  if [ "$_adguard_upstream_route" != unbound_pinned ]; then
    _dns_chain=partial
  fi
  echo "active=1"
  echo "interface=$_iface"
  echo "vpn_uid=$_uid"
  echo "egress_ipv4=$_meta_egress"
  echo "redirects=attached"
  echo "route=verified"
  echo "dns_probe=passed"
  echo "private_dns_mode=$_private_dns_mode"
  echo "dns_filter_coverage=$_coverage"
  echo "adguard_upstream_route=$_adguard_upstream_route"
  echo "dns_chain=$_dns_chain"
  return 0
}
_reconcile_route_locked() {
  if ! _is_enabled; then
    if ! _stop_locked; then
      _log "route reconcile: proxy disabled but owned cleanup is incomplete"
      return 1
    fi
    echo "active=0"
    echo "reason=disabled"
    return 0
  fi
  if [ ! -e "$ACTIVE_META" ]; then
    _reconcile_locked
    return $?
  fi
  [ -f "$ACTIVE_META" ] && [ ! -L "$ACTIVE_META" ] || {
    _stop_locked
    _log "route reconcile: active metadata is unsafe; fail-open"
    return 1
  }
  _iface=$(sed -n '1p' "$ACTIVE_META" 2>/dev/null || :)
  _uid=$(sed -n '2p' "$ACTIVE_META" 2>/dev/null || :)
  _meta_egress=$(sed -n '3p' "$ACTIVE_META" 2>/dev/null || :)
  _valid_if "$_iface" && _valid_uid "$_uid" && _valid_ipv4 "$_meta_egress" || {
    _stop_locked
    _log "route reconcile: active VPN identity is invalid; fail-open"
    return 1
  }
  if ! _adguard_upstreams_use_vpn_bound_unbound; then
    _log "route reconcile: AdGuard upstream/fallback/bootstrap is no longer pinned to FX Unbound; removing Root Proxy redirects (fail-open)"
    if ! _stop_locked; then
      echo "active=0"
      echo "reason=adguard_upstream_unpinned"
      echo "cleanup=failed"
      return 1
    fi
    echo "active=0"
    echo "reason=adguard_upstream_unpinned"
    return 0
  fi
  _current_egress=$(_resolve_vpn_egress "$_iface") || {
    _log "route reconcile: stored VPN interface $_iface no longer proves a valid egress; fail-open cleanup"
    _ensure_locked "$_iface" "$_uid"
    return $?
  }
  _stored_egress=$(tr -d '\r\n' < "$EGRESS" 2>/dev/null || :)
  if [ "$_current_egress" != "$_meta_egress" ] || [ "$_stored_egress" != "$_meta_egress" ]; then
    _log "route reconcile: VPN egress changed on $_iface ($_meta_egress -> $_current_egress); rebinding Unbound and DNS redirects"
    _ensure_locked "$_iface" "$_uid"
    return $?
  fi
  _active4=$(sed -n '1p' "$ACTIVE" 2>/dev/null || :)
  _active6=$(sed -n '2p' "$ACTIVE" 2>/dev/null || :)
  case "$_active4" in FXYRP4_A|FXYRP4_B) : ;; *) _active4= ;; esac
  case "$_active6" in FXYRP6_A|FXYRP6_B) : ;; *) _active6= ;; esac
  _whitelist_uids=$(_resolve_whitelist_uids) || {
    _log "route reconcile: current DNS exception UID set is unavailable; rebuilding through fail-open path"
    _ensure_locked "$_iface" "$_uid"
    return $?
  }
  _contract_ok=1
  [ -n "$_active4" ] && [ -n "$_active6" ] || _contract_ok=0
  if [ "$_contract_ok" = 1 ]; then
    iptables -t nat -C OUTPUT -j "$_active4" >/dev/null 2>&1 || _contract_ok=0
    ip6tables -t nat -C OUTPUT -j "$_active6" >/dev/null 2>&1 || _contract_ok=0
    _root_proxy_chain_contract 4 "$_active4" "$_uid" "$_whitelist_uids" || _contract_ok=0
    _root_proxy_chain_contract 6 "$_active6" "$_uid" "$_whitelist_uids" || _contract_ok=0
  fi
  if [ "$_contract_ok" = 1 ] && _local_dns_probe; then
    echo "active=1"
    echo "interface=$_iface"
    echo "vpn_uid=$_uid"
    echo "egress_ipv4=$_current_egress"
    echo "route=verified"
    echo "revalidated=1"
    echo "rebind=unchanged"
    return 0
  fi
  _log "route reconcile: DNS redirect generation or local DNS probe is incomplete; rebuilding current VPN binding"
  _ensure_locked "$_iface" "$_uid"
}
_package_event_locked() {
  _prune_rc=0
  _whitelist_prune_locked 0 || _prune_rc=$?
  # Route validation still runs when PackageManager cannot provide a prune
  # snapshot; stale whitelist cleanup must never suppress VPN fail-open checks.
  _reconcile_locked || return $?
  return "$_prune_rc"
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
    if [ -x "$MP/scripts/native-dns-settings.sh" ]; then
      if [ "$cmd" = enable ]; then _proxy_value=1; else _proxy_value=0; fi
      MP="$MP" PG="$PG" sh "$MP/scripts/native-dns-settings.sh" set vpn_external_dns_proxy "$_proxy_value"
    else
      if [ "$cmd" = enable ]; then pg_set vpn_external_dns_proxy 1; else pg_set vpn_external_dns_proxy 0; fi
      sh "$MP/scripts/apply.sh" fast
    fi
    ;;
  status)
    with_lock _status_locked
    ;;
  observe)
    with_lock _observe_locked
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
  whitelist-prune)
    [ "$#" -eq 1 ] || { echo "usage: yulong-root-proxy.sh whitelist-prune" >&2; exit 2; }
    with_lock _whitelist_prune_locked
    ;;
  reconcile)
    with_lock _reconcile_locked
    ;;
  reconcile-route)
    with_lock _reconcile_route_locked
    ;;
  package-event)
    [ "$#" -eq 1 ] || { echo "usage: yulong-root-proxy.sh package-event" >&2; exit 2; }
    with_lock _package_event_locked
    ;;
  uninstall)
    with_lock _stop_locked
    ;;
  *) echo 'usage: yulong-root-proxy.sh {ensure|stop|enable|disable|status|observe|whitelist-list|whitelist-set|whitelist-prune|reconcile|reconcile-route|uninstall}' >&2; exit 64 ;;
esac
