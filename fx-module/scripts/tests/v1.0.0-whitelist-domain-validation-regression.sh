#!/system/bin/sh
# Audit115: malformed whitelist entries must not become hosts exemptions or VPN DIRECT rules.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-whitelist-domain.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
cat > "$T/settings.conf" <<'CONF'
[list:domain]
valid.example.com|valid|1
VALID.EXAMPLE.COM|duplicate case variant|1
*.sub.example.net|wildcard suffix|1
bad..example.com|empty label|1
-leading.example.com|leading hyphen|1
trailing-.example.com|trailing hyphen|1
example.com.|trailing dot|1
$(not-a-domain).example|shell-like input|1
localhost|single label is hosts-only|1
[list:rule]
DOMAIN-SUFFIX,blocked.example,REJECT
CONF
OUT=$(PG="$T/pg" VPNRULE_SRC="$T/settings.conf" VPNRULE_WORK="$T/work" sh "$ROOT/scripts/vpnrule.sh" --emit)
[ "$(printf '%s\n' "$OUT" | grep -Fc '"domain_suffix":["valid.example.com"],"outbound":"direct"')" -eq 1 ] || { echo 'FAIL: valid whitelist not emitted exactly once'; exit 1; }
printf '%s\n' "$OUT" | grep -Fq '"domain_suffix":["sub.example.net"],"outbound":"direct"' || { echo 'FAIL: wildcard suffix normalization missing'; exit 1; }
for bad in 'bad..example.com' '-leading.example.com' 'trailing-.example.com' 'example.com.' '$(not-a-domain).example'; do
  if printf '%s\n' "$OUT" | grep -Fq "$bad"; then echo "FAIL: malformed whitelist emitted: $bad"; exit 1; fi
done
# Validate the hosts-side AWK guard is wired into the production generator.
grep -Fq 'function valid_domain(d, n, labels, i)' "$ROOT/scripts/apply.sh" || { echo 'FAIL: strict hosts whitelist validator missing'; exit 1; }
grep -Fq 'if (seen[d]++) next' "$ROOT/scripts/apply.sh" || { echo 'FAIL: hosts whitelist dedup missing'; exit 1; }
echo 'PASS: strict whitelist domain validation, suffix normalization, duplicate suppression, invalid entries rejected'
