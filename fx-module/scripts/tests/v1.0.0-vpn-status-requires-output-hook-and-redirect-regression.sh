#!/system/bin/sh
# Proxy status must require an installed OUTPUT hook plus a live redirect rule.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
S="$ROOT/scripts/status.sh"
grep -Fq '_VPN_HOOK=$(iptables $FWWAIT -t nat -S OUTPUT' "$S"
grep -Fq "^-A OUTPUT -j PGVPN([[:space:]]|$)|^-A OUTPUT .* -j PGVPN([[:space:]]|$)" "$S"
grep -Fq '_VPN_REDIRECT=$(printf' "$S"
grep -Fq "grep -F ' -p tcp ' | grep -F ' -j REDIRECT ' | grep -E -- '--to-ports [0-9]+'" "$S"
grep -Fq 'if [ -n "$_VPN_HOOK" ] && [ -n "$_VPN_REDIRECT" ]; then VPN_RULES_ACTIVE=true; fi' "$S"
grep -Fq 'if [ "$VPN_LISTENER_ON" = "true" ]; then VPN_ON=true; fi' "$S"
grep -Fq '"vpn_rules_active":%s,"vpn_listener_on":%s,"vpn_listener_port":%s' "$S"
if grep -Fq 'if iptables $FWWAIT -t nat -L PGVPN >/dev/null 2>&1; then VPN_ON=true; fi' "$S"; then
  echo 'FAIL: chain existence alone still marks VPN active' >&2; exit 1
fi
VPN_RE='^-A OUTPUT -j PGVPN([[:space:]]|$)|^-A OUTPUT .* -j PGVPN([[:space:]]|$)'
printf '%s\n' '-A OUTPUT -j PGVPN' | grep -E "$VPN_RE" >/dev/null
printf '%s\n' '-A OUTPUT -m comment --comment fx-proxy -j PGVPN' | grep -E "$VPN_RE" >/dev/null
if printf '%s\n' '-A OUTPUT -j PGNAT' | grep -E "$VPN_RE" >/dev/null; then echo 'FAIL: unrelated hook matched' >&2; exit 1; fi
DNS_RE='^-A OUTPUT -j PGNAT([[:space:]]|$)|^-A OUTPUT .* -j PGNAT([[:space:]]|$)'
printf '%s\n' '-A OUTPUT -j PGNAT' | grep -E "$DNS_RE" >/dev/null
printf '%s\n' '-A PGVPN -p tcp -j REDIRECT --to-ports 17996' | grep -E '^-A PGVPN ' | grep -F ' -p tcp ' | grep -F ' -j REDIRECT ' | grep -E -- '--to-ports [0-9]+' >/dev/null
printf '%s\n' '-A PGVPN -m owner --uid-owner 1000 -p tcp -j REDIRECT --to-ports 17996' | grep -E '^-A PGVPN ' | grep -F ' -p tcp ' | grep -F ' -j REDIRECT ' | grep -E -- '--to-ports [0-9]+' >/dev/null
if printf '%s\n' '-A PGVPN -p tcp -j RETURN' | grep -E '^-A PGVPN ' | grep -F ' -p tcp ' | grep -F ' -j REDIRECT ' | grep -E -- '--to-ports [0-9]+' >/dev/null; then echo 'FAIL: non-redirect rule matched' >&2; exit 1; fi
printf '%s\n' 'PASS: VPN status requires OUTPUT hook and TCP redirect; simple jump and redirect forms recognized'

# TUN status must not depend on PGVPN REDIRECT hooks; it uses verified core + fx0 UP.
grep -Fq 'if [ "$VPN_MODE" = "tun" ] && [ "$VPN_CORE_PID" != "0" ]' "$ROOT/scripts/status.sh"
grep -Fq 'ip -o link show dev fx0' "$ROOT/scripts/status.sh"
echo 'PASS: status has an independent guarded TUN health path'
