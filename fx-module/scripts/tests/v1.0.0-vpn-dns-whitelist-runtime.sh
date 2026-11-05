#!/system/bin/sh
# Runtime tests for VPN DNS whitelist normalization and domain validation.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
V="$ROOT/scripts/vpncore.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-dns-whitelist.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^vpncore_dns_whitelist_rules\(\) \{/ { active=1 } active { print } active && /^}$/ { exit }' "$V" > "$T/whitelist.sh"
[ -s "$T/whitelist.sh" ] || { echo "FAIL: DNS whitelist function not extracted" >&2; exit 1; }
PG="$T/pg"
mkdir -p "$PG/cache"
pg_list_enabled() {
  [ "$1" = domain ] && printf '%s\n' 'Trusted.Example.COM' 'plain.example.net'
}
cat > "$PG/cache/wlexc.tmp" <<'EOF'
@@||Allowed.Example.org^
@@||*.Sub.Example.org^
@@||bad..example.org^
@@||bad/path.example.org^
@@||bad_label.example.org^
EOF
. "$T/whitelist.sh"
out=$(vpncore_dns_whitelist_rules)
printf '%s\n' "$out" | grep -Fq '{"domain_suffix":["trusted.example.com"],"server":"remote"},'
printf '%s\n' "$out" | grep -Fq '{"domain_suffix":["plain.example.net"],"server":"remote"},'
printf '%s\n' "$out" | grep -Fq '{"domain_suffix":["allowed.example.org"],"server":"remote"},'
printf '%s\n' "$out" | grep -Fq '{"domain_suffix":["sub.example.org"],"server":"remote"},'
if printf '%s\n' "$out" | grep -Eq 'bad\.\.|bad/path|bad_label'; then
  echo "FAIL: malformed DNS whitelist domain was emitted" >&2
  exit 1
fi
echo 'FX VPN DNS whitelist runtime tests: PASS'
