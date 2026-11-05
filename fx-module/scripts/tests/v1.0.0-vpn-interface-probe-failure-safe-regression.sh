#!/system/bin/sh
# Guard against the catastrophic default: failed/empty `ip link` must not be
# interpreted as proof that no external VPN exists, and generic filters must
# not strand an outer VPN's socket.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
M="$ROOT/scripts/mitm-redirect.sh"
O="$ROOT/scripts/vpn-overlay-check.sh"
for f in "$A" "$M" "$O"; do sh -n "$f"; done
python3 - "$A" "$M" "$O" <<'PY'
from pathlib import Path
import sys
apply, mitm, overlay = [Path(x).read_text(encoding='utf-8') for x in sys.argv[1:]]
def need(label, ok):
    if not ok: raise SystemExit('FAIL: '+label)
d=apply.index('_PG_EXT_VPN_IF=""')
links=apply.index('_PG_LINKS=$(ip -o link show 2>/dev/null)',d)
unknown=apply.index('_PG_EXT_VPN_PROBE_UNKNOWN=1',links)
blocked=apply.index('if [ -n "$_PG_EXT_VPN_IF" ] || [ "$_PG_EXT_VPN_PROBE_UNKNOWN" = "1" ]; then',unknown)
need('apply detects before network rule setup', d < links < unknown < blocked < apply.index('# ---------- 可信 DNS 目标', blocked))
need('ip command failure and empty output both set unknown state', 'if [ "$_PG_LINK_RC" -ne 0 ] || [ -z "$_PG_LINKS" ]; then' in apply and 'else\n  _PG_EXT_VPN_PROBE_UNKNOWN=1\nfi' in apply)
need('unknown state suspends DNS and NAT interception', '[ "$_PG_VPN_INTERCEPTION_BLOCKED" = "0" ]' in apply and 'VPN interface state unknown; skip plaintext-DNS lockdown and fail-open' in apply)
need('unknown state forces proxy mode direct unless explicit, UID-verified overlay is allowed', 'if [ "$_PG_VPN_INTERCEPTION_BLOCKED" = "1" ] && [ "$VPN_MODE" != "direct" ] && [ "$VPN_EXTERNAL_COMPAT" != "1" ]; then' in apply and 'inconclusive interface probe' in apply)
need('PGUARD owner bypass is queued before generic filters', 'fw4 -I PGUARD 1 -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' in apply and 'fw6 -I PGUARD 1 -m owner --uid-owner "$VPN_EXTERNAL_UID" -j RETURN' in apply)
need('uncertain interface/UID state suppresses PGUARD hooks', 'PGUARD OUTPUT hook suppressed to preserve network/VPN' in apply and 'PGUARD OUTPUT hook suppressed to avoid breaking the outer tunnel' in apply)
need('recognized generic vpnN interface names in all independent probes', all('vpn[0-9]*' in x for x in (apply,mitm,overlay)))
need('MITM considers empty link listing unknown', '[ -n "$_links" ] || return 2' in mitm)
need('overlay tool reports interface probe uncertainty instead of no tunnel', 'interface-probe-unknown' in overlay and '[ "$_rc" -ne 0 ] || [ -z "$_links" ]' in overlay)
print('PASS: missing/error/empty VPN interface probing is fail-safe; outer VPN owner is exempted or generic filter hooks stay detached')
PY
# Live shell probe behavior with deterministic fake `ip` command.
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-probe.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin"
cat > "$T/bin/ip" <<'IP'
#!/bin/sh
case "${FX_TEST_IP_MODE:-empty}" in
  empty) exit 0 ;;
  error) exit 1 ;;
  vpn) printf '%s\n' '1: lo: <LOOPBACK>' '8: vpn0: <POINTOPOINT,UP>' ;;
esac
IP
chmod 755 "$T/bin/ip"
for mode in empty error; do
  if PATH="$T/bin:/usr/bin:/bin" PG=/nonexistent FX_TEST_IP_MODE="$mode" sh "$O" >"$T/out" 2>/dev/null; then
    echo "FAIL: overlay check accepted $mode link probe" >&2; exit 1
  else rc=$?; [ "$rc" -eq 2 ] || { echo "FAIL: $mode probe should use exit 2 (got $rc)" >&2; exit 1; }; fi
  grep -q '"status":"interface-probe-unknown"' "$T/out" || { echo "FAIL: $mode probe missing explicit unknown status" >&2; exit 1; }
done
echo 'PASS: overlay diagnostic reports empty/error interface listings as unknown'
