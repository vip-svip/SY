#!/system/bin/sh
# Regression: third-party domain/IP rejects must stay in [list:rule] and retain REJECT.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-rule-action.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
cat > "$T/sample.module" <<'MODULE'
#!name=Rule action regression
[Rule]
DOMAIN,exact.example.test,REJECT
DOMAIN-SUFFIX,suffix.example.test,REJECT
IP-CIDR,192.0.2.0/24,REJECT,no-resolve
IP-CIDR6,2001:db8::/32,REJECT,no-resolve
IP-CIDR,198.51.100.0/24,DIRECT
IP-CIDR,192.0.2.1/33,REJECT
IP-CIDR,999.0.2.1/24,REJECT
IP-CIDR6,2001:db8::/129,REJECT
IP-CIDR6,2001:db8:::/32,REJECT
MODULE
OUT=$(TMPDIR="$T" sh "$ROOT/scripts/modconvert.sh" --emit "$T/sample.module" 2>"$T/convert.err")
RULES=$(printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ {in_rule=1; next} /^\[/ {in_rule=0} in_rule && $0 !~ /^[[:space:]]*#/ && NF {print}')
[ -n "$RULES" ] || { echo 'FAIL: converter did not emit generic rules' >&2; exit 1; }
printf '%s\n' "$RULES" | grep -Fq 'DOMAIN,exact.example.test,REJECT|'
printf '%s\n' "$RULES" | grep -Fq 'DOMAIN-SUFFIX,suffix.example.test,REJECT|'
printf '%s\n' "$RULES" | grep -Fq 'IP-CIDR,192.0.2.0/24,REJECT|'
printf '%s\n' "$RULES" | grep -Fq 'IP-CIDR6,2001:db8::/32,REJECT|'
printf '%s\n' "$RULES" | grep -Fq 'ip-cidr,198.51.100.0/24,DIRECT|'
if printf '%s\n' "$RULES" | grep -Eq '192\.0\.2\.1/33|999\.0\.2\.1/24|2001:db8::/129|2001:db8:::/32'; then
  echo 'FAIL: malformed CIDR passed converter validation' >&2; exit 1
fi
FX_ROWS=$(printf '%s\n' "$OUT" | awk '/^\[list:fx\]$/ {in_fx=1; next} /^\[/ {in_fx=0} in_fx && $0 !~ /^[[:space:]]*#/ && NF {print}')
[ -z "$FX_ROWS" ] || { echo "FAIL: ordinary imported rules leaked into FX: $FX_ROWS" >&2; exit 1; }
{
  printf 'fx=0\n[list:rule]\n%s\n[list:fx]\n' "$RULES"
} > "$T/settings.conf"
JSON=$(PG="$T/pg" CONF="$T/settings.conf" VPNRULE_WORK="$T/vpnrule-work" sh "$ROOT/scripts/vpnrule.sh" --emit '' 2>"$T/vpnrule.err")
printf '%s\n' "$JSON" | grep -Fq '"domain":["exact.example.test"],"action":"reject","method":"drop"' || { echo "FAIL: exact domain reject didn't compile to reject: $JSON" >&2; exit 1; }
printf '%s\n' "$JSON" | grep -Fq '"domain_suffix":["suffix.example.test"],"action":"reject","method":"drop"' || { echo "FAIL: suffix domain reject didn't compile to reject: $JSON" >&2; exit 1; }
printf '%s\n' "$JSON" | grep -Fq '"ip_cidr":["192.0.2.0/24"],"action":"reject","method":"drop"' || { echo "FAIL: IPv4 CIDR reject was lost or became DIRECT: $JSON" >&2; exit 1; }
printf '%s\n' "$JSON" | grep -Fq '"ip_cidr":["2001:db8::/32"],"action":"reject","method":"drop"' || { echo "FAIL: IPv6 CIDR reject was lost or became DIRECT: $JSON" >&2; exit 1; }
printf '%s\n' "$JSON" | grep -Fq '"ip_cidr":["198.51.100.0/24"],"outbound":"direct"' || { echo "FAIL: explicit DIRECT IP-CIDR changed semantics: $JSON" >&2; exit 1; }
# Corrupt legacy settings must not be accepted into route JSON, otherwise one invalid
# CIDR could make the whole VPN core fail to start.
cat > "$T/bad-cidr.conf" <<'CONF'
fx=0
[list:rule]
IP-CIDR,192.0.2.0/33,REJECT|bad|1
IP-CIDR,256.0.0.1/24,REJECT|bad|1
IP-CIDR6,2001:db8::/129,REJECT|bad|1
IP-CIDR6,2001:db8:::/32,REJECT|bad|1
IP-CIDR6,2001:db8:1:2:3:4:5:6:7:8/64,REJECT|bad|1
[list:fx]
CONF
BAD_JSON=$(PG="$T/pg" CONF="$T/bad-cidr.conf" VPNRULE_WORK="$T/vpnrule-bad-work" sh "$ROOT/scripts/vpnrule.sh" --emit '' 2>"$T/vpnrule-bad.err")
[ -z "$BAD_JSON" ] || { echo "FAIL: invalid legacy CIDR leaked into route JSON: $BAD_JSON" >&2; exit 1; }
echo 'PASS: imported exact/suffix domain and IPv4/IPv6 CIDR actions persist; generic rules never enter FX'
