#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_yulong_root_proxy.py"
[ -s "$PATCHER" ] || { echo "FAIL: Yulong Root Proxy patcher missing" >&2; exit 1; }

T=$(mktemp -d "/tmp/fx-yulong-unbound.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"
PG="$T/state"
mkdir -p "$MOD/scripts" "$PG"

cat > "$MOD/scripts/unbound.sh" <<'UNBOUND'
#!/system/bin/sh
set -eu
_log() { printf '%s\n' "$*" >&2; }
_render_config() {
  cat <<EOF_CFG
server:
  verbosity: 1
  do-ip6: yes
  harden-dnssec-stripped: yes
EOF_CFG
}
_maybe_refresh_anchor() { :; }
UNBOUND
cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/system/bin/sh
    if sh "$MODDIR/scripts/adguardhome.sh" ensure "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1; then
      :
    fi
  sh "$MODDIR/scripts/adguardhome.sh" stop "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || :
  if [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then
    :
  fi
APPLY
cat > "$MOD/uninstall.sh" <<'UNINSTALL'
#!/system/bin/sh
_DNS_ENGINE_STOP_OK=1
UNINSTALL

# Apply twice to prove both the Unbound output change and lifecycle hooks are
# idempotent after the Release tree has been restored.
python3 "$PATCHER" "$MOD" "$ROOT"
python3 "$PATCHER" "$MOD" "$ROOT"

python3 - "$MOD/scripts/unbound.sh" "$MOD/scripts/apply.sh" "$MOD/uninstall.sh" <<'PY'
from pathlib import Path
import sys
unbound, apply, uninstall = map(lambda p: Path(p).read_text(encoding="utf-8"), sys.argv[1:])
assert unbound.count('_FX_OUT_IP_FILE="$PG/unbound-vpn-egress-ip"') == 1, \
    "Unbound egress marker setup must be inserted exactly once"
assert unbound.count('do-ip6: $_FX_DO_IP6') == 1, \
    "Unbound IPv6 upstream policy must be changed exactly once"
assert unbound.count("outgoing-interface: %s") == 1, \
    "Unbound must have one conditional outgoing-interface renderer"
assert apply.count('yulong-root-proxy.sh" stop') == 3, \
    "direct, failed-start and unavailable external VPN branches must each stop Root Proxy once"
assert apply.count('yulong-root-proxy.sh" ensure') == 1, \
    "external VPN branch must only start one validated Root Proxy"
assert uninstall.count('yulong-root-proxy.sh" uninstall') == 1, \
    "uninstall must stop/remove Root Proxy exactly once"
PY

render_config() {
  _pg=$1
  PG="$_pg" sh -c 'set -eu; . "$1"; _render_config' sh "$MOD/scripts/unbound.sh"
}

# Direct mode has no egress marker: preserve the default IPv6 setting and do not
# pin outgoing-interface to a stale address from an earlier VPN session.
direct=$(render_config "$PG")
printf '%s\n' "$direct" | grep -Fq 'do-ip6: yes' || {
  echo "FAIL: direct mode did not preserve default Unbound IPv6 behavior" >&2; exit 1;
}
if printf '%s\n' "$direct" | grep -Fq 'outgoing-interface:'; then
  echo "FAIL: direct mode unexpectedly pins Unbound to an old VPN interface address" >&2; exit 1
fi

# A validated marker must disable IPv6 recursive upstream transport and bind
# Unbound to the validated VPN-side IPv4 address.
printf '%s\n' "10.23.4.5" > "$PG/unbound-vpn-egress-ip"
vpn=$(render_config "$PG")
printf '%s\n' "$vpn" | grep -Fq 'do-ip6: no' || {
  echo "FAIL: VPN mode did not disable IPv6 recursive upstream transport" >&2; exit 1;
}
printf '%s\n' "$vpn" | grep -Fq 'outgoing-interface: 10.23.4.5' || {
  echo "FAIL: VPN mode did not bind Unbound to the validated egress IPv4" >&2; exit 1;
}

# Reject malformed marker data. Do not quietly produce a config that might
# bypass the third-party VPN on an unbound/default route.
printf '%s\n' "10.23.4.5;touch $T/fx-unbound-injected" > "$PG/unbound-vpn-egress-ip"
if render_config "$PG" > "$T/invalid.out" 2> "$T/invalid.err"; then
  echo "FAIL: invalid external VPN egress marker was accepted" >&2
  exit 1
fi
[ ! -e "$T/fx-unbound-injected" ] || {
  echo "FAIL: invalid egress marker caused shell execution" >&2; exit 1;
}
grep -Fq 'invalid external VPN egress marker' "$T/invalid.err" || {
  echo "FAIL: invalid marker did not produce a clear fail-closed error" >&2; cat "$T/invalid.err" >&2; exit 1;
}

# Validate the exact route-interface parser using the function extracted from the module source.
# A dot in an interface name must not act as a regular-expression wildcard.
ROUTE_HELPER="$T/route-helper.sh"
sed -n '/^_route_uses_if() {/,/^}/p' "$ROOT/fx-module/scripts/yulong-root-proxy.sh" > "$ROUTE_HELPER"
[ -s "$ROUTE_HELPER" ] || { echo "FAIL: exact route-interface helper missing" >&2; exit 1; }
. "$ROUTE_HELPER"
_route_uses_if "198.41.0.4 from 10.23.4.5 dev tun.0 src 10.23.4.5" "tun.0" || {
  echo "FAIL: exact route parser rejected the requested tunnel interface" >&2; exit 1;
}
if _route_uses_if "198.41.0.4 from 10.23.4.5 dev tunX0 src 10.23.4.5" "tun.0"; then
  echo "FAIL: route parser treated a regex-like near-match as the requested tunnel" >&2; exit 1;
fi
if _route_uses_if "198.41.0.4 from 10.23.4.5 src 10.23.4.5" "tun.0"; then
  echo "FAIL: route parser accepted output with no dev field" >&2; exit 1;
fi
if _route_uses_if "198.41.0.4 dev tun.0 dev tun1" "tun.0"; then
  echo "FAIL: route parser accepted ambiguous duplicate dev fields" >&2; exit 1;
fi
grep -Fq 'mktemp "$ACTIVE.tmp.XXXXXX"' "$ROOT/fx-module/scripts/yulong-root-proxy.sh"
grep -Fq 'mktemp "$EGRESS.tmp.XXXXXX"' "$ROOT/fx-module/scripts/yulong-root-proxy.sh"
grep -Fq 'mktemp "$ACTIVE_META.tmp.XXXXXX"' "$ROOT/fx-module/scripts/yulong-root-proxy.sh"
grep -Fq "failed to publish active chain marker" "$ROOT/fx-module/scripts/yulong-root-proxy.sh"
grep -Fq "failed to publish validated VPN egress marker" "$ROOT/fx-module/scripts/yulong-root-proxy.sh"
grep -Fq "failed to commit Root Proxy active state" "$ROOT/fx-module/scripts/yulong-root-proxy.sh"
echo "PASS: Unbound default mode, VPN-bound IPv4 egress, invalid-marker fail-closed behavior and idempotent Root Proxy patch"
