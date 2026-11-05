#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-master.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache"
cat > "$T/settings.conf" <<'__CONF__'
fx=0
[list:rule]
[list:fx]
fxfile://anti_fraud_96110|FX anti-fraud|1
__CONF__
run_emit() { PG="$T/pg" CONF="$T/settings.conf" VPNRULE_WORK="$T/work-$1" sh "$ROOT/scripts/vpnrule.sh" --emit 2>/dev/null; }
OFF=$(run_emit off)
if printf '%s\n' "$OFF" | grep -Eiq 'gjfzpt|49\.7\.228\.53'; then
  echo 'FAIL: FX rules emitted to VPN route while global fx=0' >&2; exit 1
fi
sed 's/^fx=0$/fx=1/' "$T/settings.conf" > "$T/settings.on"
mv "$T/settings.on" "$T/settings.conf"
ON=$(run_emit on)
printf '%s\n' "$ON" | grep -Fq 'gjfzpt.cn' || { echo 'FAIL: FX domain not emitted to VPN routes while fx=1' >&2; exit 1; }
printf '%s\n' "$ON" | grep -Fq '49.7.228.53/32' || { echo 'FAIL: FX IP rule not emitted to VPN routes while fx=1' >&2; exit 1; }
sh -n "$ROOT/scripts/vpnrule.sh"
echo 'PASS: FX master gates proxy route rules; bundled anti-fraud domains are compiled to VPN routes'
