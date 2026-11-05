#!/system/bin/sh
# Explicit opt-in IPv4 TCP/443 interception. Never enabled at boot/install.
# IPv6 is intentionally untouched until the engine has a verified IPv6 listener.
MODDIR=${PG_MODDIR:-${MODDIR:-}}
if [ -z "$MODDIR" ] || [ ! -f "$MODDIR/module.prop" ]; then
  _d=$(cd "$(dirname "$0")" 2>/dev/null && pwd); case "$_d" in */scripts) _d=${_d%/scripts} ;; esac; MODDIR=$_d
fi
ENGINE="$MODDIR/scripts/mitm-engine.sh"
PG=${PG:-/data/adb/privacyguard}
PORT=18443
CHAIN=PGMITM27
MARKER=PrivacyGuard-PGMITM27
IPT=$(command -v iptables 2>/dev/null)

detect_external_tunnel() {
  # Mirror apply.sh's conservative interface-name detector. This is a heuristic,
  # so an unknown detector state is handled by refusing activation, not guessing.
  command -v ip >/dev/null 2>&1 || return 2
  _links=$(ip -o link show 2>/dev/null) || return 2
  [ -n "$_links" ] || return 2
  printf '%s\n' "$_links" | sed -n 's/^[0-9][0-9]*: \([^:@]*\).*/\1/p' \
    | grep -E '^(tun[0-9]*|vpn[0-9]*|wg[0-9]*|ppp[0-9]*|ipsec[0-9]*|tap[0-9]*|utun[0-9]*|tailscale[0-9]*|zt[[:alnum:]_-]*)$' \
    | head -1
}
start_guard_watch() {
  _watch="$MODDIR/scripts/mitm-redirect-watch.sh"
  _watch_dir="$PG/mitm"
  _watch_pid="$_watch_dir/redirect-watch.pid"
  [ -x "$_watch" ] || { echo 'MITM VPN safety watcher is missing' >&2; return 1; }
  mkdir -p "$_watch_dir" 2>/dev/null || return 1
  _old_watch=$(cat "$_watch_pid" 2>/dev/null); case "$_old_watch" in ''|*[!0-9]*) _old_watch= ;; esac
  if [ -n "$_old_watch" ] && kill -0 "$_old_watch" 2>/dev/null && [ -r "/proc/$_old_watch/cmdline" ] && \
     tr '\000' '\n' < "/proc/$_old_watch/cmdline" 2>/dev/null | grep -Fx "$_watch" >/dev/null 2>&1; then
    return 0
  fi
  rm -f "$_watch_pid"
  nohup sh "$_watch" "$MODDIR" >>"$_watch_dir/redirect-watch.log" 2>&1 &
  _new_watch=$!
  echo "$_new_watch" > "$_watch_pid" || return 1
  chmod 600 "$_watch_pid" 2>/dev/null || :
  sleep 1
  if kill -0 "$_new_watch" 2>/dev/null && [ -r "/proc/$_new_watch/cmdline" ] && \
     tr '\000' '\n' < "/proc/$_new_watch/cmdline" 2>/dev/null | grep -Fx "$_watch" >/dev/null 2>&1; then
    return 0
  fi
  rm -f "$_watch_pid"
  return 1
}
has_vpn_jump() {
  # Do not coexist with either the IPv4 or IPv6 transparent VPN redirect.
  if [ -n "$IPT" ] && "$IPT" -t nat -S OUTPUT 2>/dev/null | grep -E -- '(-j|-g) PGVPN( |$)' >/dev/null 2>&1; then
    return 0
  fi
  _IPT6=$(command -v ip6tables 2>/dev/null)
  if [ -n "$_IPT6" ] && "$_IPT6" -t nat -S OUTPUT 2>/dev/null | grep -E -- '(-j|-g) PGVPN6( |$)' >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
owned_chain() {
  [ -n "$IPT" ] || return 1
  "$IPT" -t nat -S "$CHAIN" 2>/dev/null | grep -F -- "--comment $MARKER" >/dev/null 2>&1
}
redirect_rule_present() {
  [ -n "$IPT" ] || return 1
  "$IPT" -t nat -C "$CHAIN" -p tcp --dport 443 -m comment --comment "$MARKER" -j REDIRECT --to-ports "$PORT" >/dev/null 2>&1
}
chain_rules_complete() {
  [ -n "$IPT" ] || return 1
  owned_chain && \
    "$IPT" -t nat -C "$CHAIN" -d 127.0.0.0/8 -m comment --comment "$MARKER" -j RETURN >/dev/null 2>&1 && \
    "$IPT" -t nat -C "$CHAIN" -d 10.0.0.0/8 -j RETURN >/dev/null 2>&1 && \
    "$IPT" -t nat -C "$CHAIN" -d 172.16.0.0/12 -j RETURN >/dev/null 2>&1 && \
    "$IPT" -t nat -C "$CHAIN" -d 192.168.0.0/16 -j RETURN >/dev/null 2>&1 && \
    "$IPT" -t nat -C "$CHAIN" -d 169.254.0.0/16 -j RETURN >/dev/null 2>&1 && \
    "$IPT" -t nat -C "$CHAIN" -d 224.0.0.0/4 -j RETURN >/dev/null 2>&1 && \
    "$IPT" -t nat -C "$CHAIN" -m owner --uid-owner 0 -j RETURN >/dev/null 2>&1 && \
    redirect_rule_present
}
remove_family() {
  # Never report cleanup success when the firewall tool is unavailable: the
  # redirect may still be installed and could continue capturing traffic.
  [ -n "$IPT" ] || { echo "iptables unavailable; cannot verify or remove $CHAIN" >&2; return 1; }
  if "$IPT" -t nat -S "$CHAIN" >/dev/null 2>&1; then
    owned_chain || { echo "refusing to alter unowned NAT chain $CHAIN" >&2; return 1; }
    _rm_count=0
    while "$IPT" -t nat -C OUTPUT -j "$CHAIN" >/dev/null 2>&1; do
      _rm_count=$((_rm_count + 1))
      # Defend against broken wrappers or firewall backends that report a
      # successful delete without changing state. Cleanup must never hang.
      [ "$_rm_count" -le 64 ] || { echo "too many OUTPUT jumps for $CHAIN; refusing unbounded cleanup" >&2; return 1; }
      "$IPT" -t nat -D OUTPUT -j "$CHAIN" >/dev/null 2>&1 || return 1
    done
    "$IPT" -t nat -F "$CHAIN" >/dev/null 2>&1 || return 1
    "$IPT" -t nat -X "$CHAIN" >/dev/null 2>&1 || return 1
  fi
  return 0
}
# Cleanup is permitted only after install_family has established ownership
# (existing marker-verified chain or a chain created by this invocation).
rollback_partial_install() {
  [ "${PGMITM_CAN_CLEAN:-0}" = 1 ] || return 1
  [ -n "$IPT" ] || return 1
  _rb_count=0
  while "$IPT" -t nat -C OUTPUT -j "$CHAIN" >/dev/null 2>&1; do
    _rb_count=$((_rb_count + 1))
    [ "$_rb_count" -le 64 ] || { echo "too many OUTPUT jumps for $CHAIN during rollback" >&2; return 1; }
    "$IPT" -t nat -D OUTPUT -j "$CHAIN" >/dev/null 2>&1 || return 1
  done
  "$IPT" -t nat -F "$CHAIN" >/dev/null 2>&1 || return 1
  "$IPT" -t nat -X "$CHAIN" >/dev/null 2>&1 || return 1
  return 0
}
install_family() {
  [ -n "$IPT" ] || return 1
  PGMITM_CAN_CLEAN=0
  if "$IPT" -t nat -S "$CHAIN" >/dev/null 2>&1; then
    owned_chain || { echo "refusing to reuse unowned NAT chain $CHAIN" >&2; return 1; }
    PGMITM_CAN_CLEAN=1
    # Idempotent enable only if the attached chain is complete. A chain can
    # survive a power loss halfway through rule installation; never report that
    # partial state as enabled.
    if "$IPT" -t nat -C OUTPUT -j "$CHAIN" >/dev/null 2>&1 && chain_rules_complete; then
      return 0
    fi
    "$IPT" -t nat -F "$CHAIN" || { rollback_partial_install; return 1; }
  else
    "$IPT" -t nat -N "$CHAIN" || return 1
    PGMITM_CAN_CLEAN=1
  fi
  # Install ownership marker first so every later partial state is identifiable.
  "$IPT" -t nat -A "$CHAIN" -d 127.0.0.0/8 -m comment --comment "$MARKER" -j RETURN || { rollback_partial_install; return 1; }
  # Do not intercept loopback, local/LAN services, link-local or multicast.
  "$IPT" -t nat -A "$CHAIN" -d 10.0.0.0/8 -j RETURN || { rollback_partial_install; return 1; }
  "$IPT" -t nat -A "$CHAIN" -d 172.16.0.0/12 -j RETURN || { rollback_partial_install; return 1; }
  "$IPT" -t nat -A "$CHAIN" -d 192.168.0.0/16 -j RETURN || { rollback_partial_install; return 1; }
  "$IPT" -t nat -A "$CHAIN" -d 169.254.0.0/16 -j RETURN || { rollback_partial_install; return 1; }
  "$IPT" -t nat -A "$CHAIN" -d 224.0.0.0/4 -j RETURN || { rollback_partial_install; return 1; }
  "$IPT" -t nat -A "$CHAIN" -m owner --uid-owner 0 -j RETURN || { rollback_partial_install; return 1; }
  "$IPT" -t nat -A "$CHAIN" -p tcp --dport 443 -m comment --comment "$MARKER" -j REDIRECT --to-ports "$PORT" || { rollback_partial_install; return 1; }
  "$IPT" -t nat -I OUTPUT 1 -j "$CHAIN" || { rollback_partial_install; return 1; }
  return 0
}
case "${1:-status}" in
  enable)
    [ "$(id -u 2>/dev/null)" = 0 ] || { echo 'root required' >&2; exit 2; }
    [ -n "$IPT" ] || { echo 'IPv4 iptables unavailable' >&2; exit 2; }
    _external_if=$(detect_external_tunnel)
    _detect_rc=$?
    if [ "$_detect_rc" -eq 2 ]; then
      echo 'refusing: cannot inspect network interfaces; external VPN state is unknown' >&2
      exit 3
    fi
    if [ -n "$_external_if" ]; then
      echo "refusing: external VPN tunnel $_external_if detected; disable it before enabling experimental MITM" >&2
      exit 3
    fi
    if has_vpn_jump; then
      echo 'refusing: PGVPN/PGVPN6 redirect is active; disable VPN redirect first' >&2
      exit 3
    fi
    # Fail closed unless the exact runtime CA is present in the system trust view
    # and the dedicated child certificate module is released/enabled. Merely
    # having a PEM file or a running listener is not sufficient: redirecting
    # traffic to an untrusted CA would turn HTTPS into widespread TLS failures.
    _mitm_status=$(sh "$ENGINE" status 2>/dev/null) || {
      echo '{"ok":false,"error":"cannot determine MITM CA/trust state; redirect not installed"}' >&2
      exit 4
    }
    case "$_mitm_status" in
      *'"ca_submodule":"released"'*'"ca_system_trust":"present"'*) : ;;
      *'"ca_submodule":"released"'*'"ca_system_trust":"present"'* ) : ;;
      *)
        echo '{"ok":false,"error":"MITM CA is not confirmed active in the system trust store; run scripts/mitm-engine.sh trust-ca and verify status before enabling redirect"}' >&2
        exit 4
        ;;
    esac
    # Without an explicit host allowlist this redirect cannot perform useful
    # script/TLS work. Refuse a broad all-443 detour rather than silently routing
    # every public HTTPS connection through an empty MITM configuration.
    [ -x "$MODDIR/scripts/sync-mitm-hosts.sh" ] || {
      echo 'MITM hostname synchronizer missing; refusing broad HTTPS redirect' >&2
      exit 4
    }
    _hosts_sync=$(FX_MODDIR="$MODDIR" PG="$PG" sh "$MODDIR/scripts/sync-mitm-hosts.sh" 2>&1)
    _hosts_rc=$?
    if [ "$_hosts_rc" -ne 0 ]; then
      echo "MITM hostname synchronization failed; redirect not installed: $_hosts_sync" >&2
      exit 4
    fi
    if [ ! -s "$PG/mitm/hostnames.conf" ]; then
      echo 'MITM hostname allowlist is empty; add and enable one or more [list:mitmhost] hostnames before enabling redirect' >&2
      exit 4
    fi
    # IPv4 only: do not install a broken IPv6 redirect.
    sh "$ENGINE" start || { echo 'MITM listener failed; no redirect installed' >&2; exit 1; }
    if ! install_family; then
      remove_family || :
      sh "$ENGINE" stop >/dev/null 2>&1
      echo 'IPv4 redirect setup failed; attempted rollback' >&2
      exit 1
    fi
    # Once enabled, a small opt-in-only watcher removes our redirect if a known
    # external tunnel appears later; it never edits any third-party firewall chain.
    if ! start_guard_watch; then
      remove_family || :
      sh "$ENGINE" stop >/dev/null 2>&1
      echo 'VPN safety watcher failed to start; redirect rolled back' >&2
      exit 1
    fi
    echo '{"ok":true,"redirect":"enabled","family":"IPv4 only","scope":"explicit opt-in public IPv4 TCP/443; TLS termination restricted to configured MITM hostnames; other hosts pass through","vpn_guard":"known external tunnel detected before enable and monitored while enabled","limitations":"HTTP/1.1 only; IPv6 untouched; QUIC/pinning/custom TLS stacks unsupported"}'
    ;;
  disable-rules)
    # Internal lifecycle primitive: remove only our firewall rules, without
    # stopping the listener. Used by mitm-engine.sh stop to prevent redirecting
    # traffic into a closed port.
    remove_family || exit 1
    echo '{"ok":true,"ipv4_redirect":"disabled"}'
    ;;
  disable)
    remove_family || exit 1
    if ! sh "$ENGINE" stop >/dev/null 2>&1; then
      echo '{"ok":false,"redirect":"disabled","listener":"stop-failed"}' >&2
      exit 1
    fi
    echo '{"ok":true,"redirect":"disabled","family":"IPv4 only","listener":"stopped"}'
    ;;
  external-vpn)
    _external_if=$(detect_external_tunnel)
    _detect_rc=$?
    if [ "$_detect_rc" -eq 2 ]; then echo 'external VPN state unknown: interface listing unavailable, failed, or empty' >&2; exit 2; fi
    if [ -n "$_external_if" ]; then printf '%s\n' "$_external_if"; exit 0; fi
    exit 1
    ;;
  status)
    # A missing firewall frontend means status is unknown, not disabled.
    [ -n "$IPT" ] || { echo '{"ok":false,"ipv4_redirect":"unknown","error":"iptables unavailable; cannot verify redirect state"}'; exit 2; }
    _state=disabled
    if "$IPT" -t nat -S "$CHAIN" >/dev/null 2>&1; then
      owned_chain || { echo '{"ok":false,"error":"chain name collision; ownership marker absent"}'; exit 2; }
      if "$IPT" -t nat -C OUTPUT -j "$CHAIN" >/dev/null 2>&1; then
        if chain_rules_complete; then
          _state=enabled
        else
          echo '{"ok":false,"ipv4_redirect":"partial","error":"owned chain is attached but expected exclusions or REDIRECT rule are missing"}'
          exit 2
        fi
      else
        # A detached but owned chain is stale state, not a clean disabled state.
        echo '{"ok":false,"ipv4_redirect":"orphaned-chain","error":"owned PGMITM27 chain exists without an OUTPUT jump; inspect before cleanup"}'
        exit 2
      fi
    elif "$IPT" -t nat -C OUTPUT -j "$CHAIN" >/dev/null 2>&1; then
      echo '{"ok":false,"ipv4_redirect":"unknown","error":"OUTPUT references a chain that cannot be inspected"}'
      exit 2
    fi
    # A redirect without its listener is a degraded state: traffic may be
    # redirected into a closed local port after a crash. Report both facts;
    # status remains read-only and never mutates firewall rules.
    _listener=unknown
    _pidfile=/data/adb/privacyguard/mitm/engine.pid
    _bin="$MODDIR/bin/arm64/pg-mitm"
    [ -x "$_bin" ] || _bin="$MODDIR/bin/arm/pg-mitm"
    _pid=$(cat "$_pidfile" 2>/dev/null)
    case "$_pid" in ''|*[!0-9]*) _pid= ;; esac
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null && [ -r "/proc/$_pid/cmdline" ]; then
      _argv0=$(tr '\000' '\n' < "/proc/$_pid/cmdline" 2>/dev/null | sed -n '1p')
      if [ -n "$_argv0" ] && [ "$_argv0" = "$_bin" ]; then
        if [ -x "$MODDIR/scripts/mitm-listener-health.sh" ] && \
           (unset PG_PROC_NET_TCP; sh "$MODDIR/scripts/mitm-listener-health.sh" check) >/dev/null 2>&1; then
          _listener=running
        else
          _listener=unhealthy
        fi
      else
        _listener=stopped
      fi
    else
      _listener=stopped
    fi
    _health=ok
    if [ "$_state" = enabled ] && [ "$_listener" != running ]; then _health=degraded; fi
    echo "{\"ipv4_redirect\":\"$_state\",\"ipv6_redirect\":\"untouched\",\"listener\":\"$_listener\",\"health\":\"$_health\",\"mode\":\"opt-in\"}"
    ;;
  *) echo 'usage: mitm-redirect.sh enable|disable|status|external-vpn' >&2; exit 2 ;;
esac
