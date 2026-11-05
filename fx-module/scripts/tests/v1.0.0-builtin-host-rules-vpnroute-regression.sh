#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T="${TMPDIR:-/tmp}/pg-builtin-route-$$"
mkdir -p "$T/pg/cache" "$T/work"
trap 'rm -rf "$T"' EXIT HUP INT TERM
cat > "$T/settings.conf" <<'__CONF__'
fx=0
[list:rule]
builtin://privacy_ad_domains|ad domains|1
builtin://AdultSite_AdHosts.txt|adult ad networks|1
builtin://AdultSite_AdPopup.txt|cosmetic only|1
[list:fx]
__CONF__
PG="$T/pg" CONF="$T/settings.conf" VPNRULE_SRC="$T/settings.conf" VPNRULE_WORK="$T/work" sh "$ROOT/scripts/vpnrule.sh" --emit > "$T/emit.json"
# A bundled hosts file must produce reject rules even when hosts_block is disabled.
for d in exoclick.com trafficjunky.net; do
  grep -Fq "\"domain_suffix\":[\"$d\"]" "$T/emit.json" || { echo "FAIL: missing route reject for $d" >&2; exit 1; }
done
[ "$(grep -o '"domain_suffix":\["exoclick.com"\]' "$T/emit.json" | wc -l | tr -d ' ')" = 1 ] || { echo 'FAIL: duplicate builtin domain route rows were not collapsed' >&2; exit 1; }
# Cosmetic selectors must never leak into sing-box route rules.
if grep -Eiq 'watermark|ad-container|popup-ad|css' "$T/emit.json"; then echo 'FAIL: CSS cosmetic selector entered VPN route rules' >&2; exit 1; fi
echo 'PASS: built-in ad-host domains feed the VPN route compiler; cosmetic selectors stay in MITM layer'
