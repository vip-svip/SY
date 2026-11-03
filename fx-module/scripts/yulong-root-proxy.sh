#!/system/bin/sh
# DNS Root Proxy fallback over a validated third-party Android VPN.
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
mkdir -p "$PG"

_log() { printf '[%s] yulong-root-proxy: %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || :; }
_valid_uid() { case "${1:-}" in ''|*[!0-9]*|0) return 1;; *) return 0;; esac; }
_valid_if() { case "${1:-}" in ''|*[!A-Za-z0-9_.:-]*) return 1;; *) return 0;; esac; }
_valid_ipv4() {
  printf '%s\n' "$1" | awk -F. '
    NF != 4 {ok=0; exit}
    {ok=1; for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || length($i)>3 || ($i+0)>255) ok=0}
    END {exit(ok ? 0 : 1)}
  '
}
_is_enabled() {
  [ "$(pg_get vpn_external_dns_proxy 1 2>/dev/null)" = "1" ] \
    && [ "$(pg_get vpn_external_compat 1 2>/dev/null)" = "1" ] \
    && [ "$(pg_get dns_forward 1 2>/dev/null)" = "1" ]
}
_remove_hook() {
  _bin="$1"; _chain="$2"
  while "$_bin" -t nat -D OUTPUT -j "$_chain" >/dev/null 2>&1; do :; done
  return 0
}
_clear_chain() {
  _bin="$1"; _chain="$2"
  _remove_hook "$_bin" "$_chain" || :
  "$_bin" -t nat -F "$_chain" >/dev/null 2>&1 || :
  "$_bin" -t nat -X "$_chain" >/dev/null 2>&1 || :
  return 0
}
_clear_all() {
  for c in FXYRP4_A FXYRP4_B; do _clear_chain iptables "$c"; done
  for c in FXYRP6_A FXYRP6_B; do _clear_chain ip6tables "$c"; done
  rm -f "$ACTIVE" "$ACTIVE_META" "$EGRESS" "$EGRESS.tmp."* 2>/dev/null || :
}
_stop_engines() {
  sh "$MP/scripts/adguardhome.sh" stop "$MP" "$PG" >> "$LOG" 2>&1 || :
  sh "$MP/scripts/unbound.sh" stop "$MP" "$PG" >> "$LOG" 2>&1 || :
}
_stop_locked() {
  _clear_all
  _stop_engines
  _log "stopped; removed only FX-owned DNS redirection chains"
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
  for _dest in 198.41.0.4 199.9.14.201; do
    _route=$(ip route get "$_dest" from "$_ip" 2>/dev/null) || {
      _log "route lookup failed through tunnel source $_ip for $_dest"; return 1;
    }
    printf '%s\n' "$_route" | grep -Eq "(^|[[:space:]])dev[[:space:]]+${_if}([[:space:]]|$)" || {
      _log "route for $_dest from $_ip does not use $_if: $_route"; return 1;
    }
  done
  printf '%s\n' "$_ip"
}
_build_chain4() {
  _chain="$1"; _uid="$2"
  iptables -t nat -N "$_chain" >/dev/null 2>&1 || iptables -t nat -F "$_chain" || return 1
  iptables -t nat -A "$_chain" -m owner --uid-owner 0 -j RETURN || return 1
  iptables -t nat -A "$_chain" -m owner --uid-owner "$_uid" -j RETURN || return 1
  iptables -t nat -A "$_chain" -d 127.0.0.0/8 -j RETURN || return 1
  iptables -t nat -A "$_chain" -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:53 || return 1
  iptables -t nat -A "$_chain" -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:53 || return 1
}
_build_chain6() {
  _chain="$1"; _uid="$2"
  ip6tables -t nat -N "$_chain" >/dev/null 2>&1 || ip6tables -t nat -F "$_chain" || return 1
  ip6tables -t nat -A "$_chain" -m owner --uid-owner 0 -j RETURN || return 1
  ip6tables -t nat -A "$_chain" -m owner --uid-owner "$_uid" -j RETURN || return 1
  ip6tables -t nat -A "$_chain" -d ::1/128 -j RETURN || return 1
  ip6tables -t nat -A "$_chain" -p udp --dport 53 -j DNAT --to-destination '[::1]:53' || return 1
  ip6tables -t nat -A "$_chain" -p tcp --dport 53 -j DNAT --to-destination '[::1]:53' || return 1
}
_activate_chains() {
  _uid="$1"
  _current=$(awk 'NR==1 {print $1}' "$ACTIVE" 2>/dev/null)
  case "$_current" in FXYRP4_A) _n4=FXYRP4_B; _o4=FXYRP4_A;; FXYRP4_B) _n4=FXYRP4_A; _o4=FXYRP4_B;; *) _n4=FXYRP4_A; _o4=FXYRP4_B;; esac
  case "$_current" in FXYRP4_A) _n6=FXYRP6_B; _o6=FXYRP6_A;; FXYRP4_B) _n6=FXYRP6_A; _o6=FXYRP6_B;; *) _n6=FXYRP6_A; _o6=FXYRP6_B;; esac
  _build_chain4 "$_n4" "$_uid" || {
    _clear_chain iptables "$_n4"; _log "IPv4 DNS chain build failed"; return 1;
  }
  _build_chain6 "$_n6" "$_uid" || {
    _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"
    _log "IPv6 NAT is unavailable or its chain failed; no DNS redirect activated"
    return 1
  }
  iptables -t nat -I OUTPUT 1 -j "$_n4" || {
    _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; return 1;
  }
  ip6tables -t nat -I OUTPUT 1 -j "$_n6" || {
    _remove_hook iptables "$_n4"
    _clear_chain iptables "$_n4"; _clear_chain ip6tables "$_n6"; return 1
  }
  _remove_hook iptables "$_o4"
  _remove_hook ip6tables "$_o6"
  _clear_chain iptables "$_o4"
  _clear_chain ip6tables "$_o6"
  printf '%s\n%s\n' "$_n4" "$_n6" > "$ACTIVE.tmp.$$"
  chmod 600 "$ACTIVE.tmp.$$" && mv -f "$ACTIVE.tmp.$$" "$ACTIVE"
}
_ensure_locked() {
  _iface="$1"; _uid="$2"
  if ! _is_enabled; then
    _stop_locked
    _log "disabled by settings or DNS forwarding off"
    return 0
  fi
  _valid_uid "$_uid" && _valid_if "$_iface" || {
    _stop_locked; _log "missing unique active VPN owner UID/interface; fail-open"; return 1;
  }
  _egress=$(_resolve_vpn_egress "$_iface") || {
    _stop_locked; _log "VPN egress route could not be proven; fail-open"; return 1;
  }
  printf '%s\n' "$_egress" > "$EGRESS.tmp.$$" || return 1
  chmod 600 "$EGRESS.tmp.$$" && mv -f "$EGRESS.tmp.$$" "$EGRESS" || return 1

  if ! sh "$MP/scripts/unbound.sh" ensure "$MP" "$PG" >> "$LOG" 2>&1; then
    _stop_locked; _log "Unbound failed to bind through the external VPN; fail-open"; return 1;
  fi
  if ! sh "$MP/scripts/adguardhome.sh" ensure "$MP" "$PG" >> "$LOG" 2>&1; then
    _stop_locked; _log "AdGuard Home failed local DNS health checks; fail-open"; return 1;
  fi
  if ! command -v nslookup >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1 \
      || ! timeout 5 nslookup example.com 127.0.0.1 2>&1 \
             | grep -Eq 'Address[[:space:]]+[0-9]+:[[:space:]]*[0-9]{1,3}(\.[0-9]{1,3}){3}|[0-9]{1,3}(\.[0-9]{1,3}){3}'; then
    _stop_locked; _log "post-start DNS probe failed; fail-open"; return 1;
  fi
  _activate_chains "$_uid" || {
    _stop_locked; _log "dual-stack DNS NAT setup failed; fail-open"; return 1;
  }
  printf '%s\n%s\n%s\n%s\n' "$_iface" "$_uid" "$_egress" "$(date '+%s')" > "$ACTIVE_META.tmp.$$"
  chmod 600 "$ACTIVE_META.tmp.$$" && mv -f "$ACTIVE_META.tmp.$$" "$ACTIVE_META"
  _log "active: AdGuard DNS filtering is local; Unbound egress is pinned to $_egress on $_iface; VPN owner UID $_uid bypasses redirect"
  echo "active=1"
  echo "interface=$_iface"
  echo "vpn_uid=$_uid"
  echo "egress_ipv4=$_egress"
}
with_lock() {
  _tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    _owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
    case "$_owner" in
      ''|*[!0-9]*)
        # Allow the owner to publish its PID immediately after mkdir.
        if [ ! -e "$LOCK/pid" ] && [ "$_tries" -ge 3 ]; then
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
      *)
        if ! kill -0 "$_owner" 2>/dev/null; then
          rm -f "$LOCK/pid" 2>/dev/null || :
          rmdir "$LOCK" 2>/dev/null || :
        fi
        ;;
    esac
    _tries=$((_tries+1))
    [ "$_tries" -lt 20 ] || { echo "root DNS proxy update is busy" >&2; return 10; }
    sleep 1
  done
  if ! printf '%s\n' "$$" > "$LOCK/pid"; then
    rmdir "$LOCK" 2>/dev/null || :
    echo "cannot record root DNS proxy lock owner" >&2
    return 10
  fi
  cleanup_lock() {
    rm -f "$LOCK/pid" 2>/dev/null || :
    rmdir "$LOCK" 2>/dev/null || :
  }
  # Signal handlers exit first; EXIT performs the one authoritative cleanup.
  trap cleanup_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  "$@"
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
    echo "enabled=$(pg_get vpn_external_dns_proxy 1)"
    echo "dns_forward=$(pg_get dns_forward 1)"
    if [ -s "$ACTIVE_META" ]; then
      sed -n '1,4p' "$ACTIVE_META" | sed '1s/^/interface=/;2s/^/vpn_uid=/;3s/^/egress_ipv4=/;4s/^/activated_at=/'
      echo "active=1"
    else
      echo "active=0"
    fi
    ;;
  uninstall)
    with_lock _stop_locked
    ;;
  *) echo 'usage: yulong-root-proxy.sh {ensure|stop|enable|disable|status|uninstall}' >&2; exit 64 ;;
esac
