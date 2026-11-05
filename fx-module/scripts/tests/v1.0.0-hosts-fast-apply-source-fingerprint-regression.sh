#!/system/bin/sh
# Regression for file-only edits: fast apply fingerprint must include local hosts
# and editable rule sources, not just settings.conf.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-host-fingerprint.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache" "$T/pg/local" "$T/pg/fxrules-user" "$T/pg/rulefiles-user" "$T/mod/rulefiles" "$T/mod/fxrules"
export PG="$T/pg" CONF="$T/settings.conf" MODDIR="$T/mod"
printf 'hosts_block=1\n' > "$CONF"
printf '0.0.0.0 one.example\n' > "$PG/local/hosts"
# Extract the production helper, then execute it against isolated paths.
awk '/^pg_hosts_input_signature\(\) \{/ {p=1} p {print} p && /^}/ {exit}' "$A" > "$T/fn.sh"
test -s "$T/fn.sh"
. "$T/fn.sh"
sig1=$(pg_hosts_input_signature)
printf '0.0.0.0 two.example\n' > "$PG/local/hosts"
sig2=$(pg_hosts_input_signature)
test "$sig1" != "$sig2"
printf 'DOMAIN-SUFFIX,custom.example,REJECT\n' > "$PG/fxrules-user/custom.txt"
sig3=$(pg_hosts_input_signature)
test "$sig2" != "$sig3"
printf '127.0.0.1 bundled.example\n' > "$MODDIR/rulefiles/one.txt"
sig4=$(pg_hosts_input_signature)
test "$sig3" != "$sig4"
printf 'hosts_block=0\n' > "$CONF"
sig5=$(pg_hosts_input_signature)
test "$sig4" != "$sig5"
grep -Fq 'pg_hosts_input_signature' "$A"
grep -Fq 'hosts-config.cksum' "$A"
grep -Fq 'subnet-ips.list.stage.$$' "$A"
grep -Fq '保留上一份 hosts 与 IP 规则' "$A"
grep -Fq 'quick apply refuses network fetch' "$A"
echo 'FX fast-apply hosts input fingerprint regression: PASS (local file, user rules, bundled rules, config)'
