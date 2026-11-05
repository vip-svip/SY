#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"; HTML="$ROOT/webroot/index.html"; UTIL="$ROOT/scripts/util.sh"; BOOT="$ROOT/post-fs-data.sh"; APPLY="$ROOT/scripts/apply.sh"
for key in ad_filter_master dns_block hosts_block mitm_block ip_block waf_block; do
  if grep -Fq "data-key=\"$key\"" "$HTML"; then echo "FAIL: retired UI switch remains: $key" >&2; exit 1; fi
  if grep -Eq "^${key}=" "$CONF"; then echo "FAIL: fresh defaults seed retired switch $key" >&2; exit 1; fi
done
if grep -Fq 'data-key="ad_protection_master"' "$HTML" || grep -Eq '^ad_protection_master=' "$CONF" || grep -Fq 'ad_protection_master' "$APPLY"; then echo 'FAIL: old master still executes' >&2; exit 1; fi
grep -Fq 'pg_list_enabled block' "$APPLY"
grep -Fq 'pg_list_enabled "$_asect"' "$APPLY"
grep -Fq '_HOSTS_BLOCK_EFFECTIVE' "$BOOT"
grep -Fq 'migrate-legacy-block-rows-v1.done' "$UTIL"
grep -Fq 'legacy MITM/WAF IP/domain rows migrated to individually enabled [list:block] entries' "$UTIL"
if grep -Fq 'pg_get dns_block 0' "$APPLY"; then echo 'FAIL: old DNS category gate remains' >&2; exit 1; fi
sh -n "$UTIL"; sh -n "$BOOT"; sh -n "$APPLY"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/fx-per-rule.XXXXXX"); trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/settings.conf" <<'CONF'
[list:block]
192.0.2.40|single IP|1
example.org|single domain|0
CONF
PG="$tmp"
CONF="$tmp/settings.conf"
export PG CONF
. "$UTIL"
_actual=$(pg_list_enabled block)
[ "$_actual" = '192.0.2.40' ] || { printf 'FAIL: per-row enabled state not authoritative (got: <%s>)\n' "$_actual" >&2; exit 1; }
echo 'PASS: retired category controls removed; individual rows drive engines'
