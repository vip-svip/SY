#!/system/bin/sh
# Audit114: keep only narrow connectivity/time defaults in the FX whitelist.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
section=$(awk '/^\[list:domain\]/{on=1;next}/^\[/{on=0}on{print}' "$CONF")
for d in connectivitycheck.gstatic.com connectivitycheck.platform.hicloud.com connect.rom.miui.com www.msftconnecttest.com msftconnecttest.com msftncsi.com captive.apple.com time.android.com time.windows.com pool.ntp.org; do
  printf '%s\n' "$section" | awk -F'|' -v d="$d" 'tolower($1)==tolower(d) && $3=="1" {found=1} END{exit !found}' || { echo "FAIL: missing default whitelist $d"; exit 1; }
done
# Broad provider roots must never be default allowlisted.
if printf '%s\n' "$section" | grep -Eiq '^(google\.com|apple\.com|microsoft\.com)\|'; then
  echo 'FAIL: overly broad provider root in default whitelist'; exit 1
fi
# Existing hosts generator and VPN route compiler must consume [list:domain].
grep -Fq 'pg_list_enabled domain' "$ROOT/scripts/apply.sh" || { echo 'FAIL: hosts pipeline no longer consumes whitelist'; exit 1; }
grep -Fq 'DOMAIN-SUFFIX,' "$ROOT/scripts/vpnrule.sh" || { echo 'FAIL: VPN whitelist DIRECT route generation missing'; exit 1; }
echo 'PASS: narrow connectivity/time whitelist defaults, no broad provider roots, hosts and VPN whitelist integration present'
