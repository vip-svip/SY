#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
F="$ROOT/scripts/fileedit.sh"
V="$ROOT/scripts/vpnrule.sh"
# The UI-edited local hosts source is an extensionless file separate from the generated system view.
grep -Fq 'base="$PG/local/hosts"; ov=""; name="hosts"' "$F"
grep -Fq 'hosts_parse_file "$_F" "$_FIP" "$WL_EXC" >/dev/null' "$A"
if grep -Fq '系统 hosts 为只读视图' "$F"; then echo 'legacy readonly guard remains' >&2; exit 1; fi
# Exercise subscription compilation without network: only a cache with matching SHA-256 is consumed.
T=${TMPDIR:-/tmp}/fx-subroute-test.$$
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/cache/rules" "$T/work"
URL='https://rules.example/test.txt'
KEY=$(printf '%s' "$URL" | cksum | awk '{print $1}')
printf '0.0.0.0 ads.example.com\n||tracker.example.net^\n@@||safe.example.org^\nDOMAIN-SUFFIX,clash.example,REJECT\n' > "$T/cache/rules/$KEY"
sha256sum "$T/cache/rules/$KEY" | awk '{print $1}' > "$T/cache/rules/$KEY.sha256"
cat > "$T/settings.conf" <<CONF
[list:rule]
$URL|fixture|1
[list:domain]
safe.example.org|whitelist|1
CONF
PG="$T" CONF="$T/settings.conf" VPNRULE_WORK="$T/work" sh "$V" --emit > "$T/out"
grep -q '"domain_suffix":\["ads.example.com"\].*"action":"reject"' "$T/out"
grep -q '"domain_suffix":\["tracker.example.net"\].*"action":"reject"' "$T/out"
grep -q '"domain_suffix":\["safe.example.org"\].*"outbound":"direct"' "$T/out"
grep -q '"domain_suffix":\["clash.example"\].*"action":"reject"' "$T/out"
# Whitelist DIRECT must be ordered before subscription REJECT entries.
wl_pos=$(grep -bo 'safe.example.org' "$T/out" | head -1 | cut -d: -f1)
block_pos=$(grep -bo 'ads.example.com' "$T/out" | head -1 | cut -d: -f1)
[ "$wl_pos" -lt "$block_pos" ]
echo 'FX hosts/subscription separation regression: PASS'
