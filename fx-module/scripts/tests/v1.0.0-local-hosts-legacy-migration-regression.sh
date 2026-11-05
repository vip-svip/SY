#!/system/bin/sh
# Host-runnable regression: legacy list entries migrate once into local/hosts,
# disabled entries remain comments, and repeated apply does not duplicate entries.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/pg/local" "$TMP/pg/cache"
cat > "$TMP/settings.conf" <<'CONF'
[list:hosts_local]
0.0.0.0 enabled.example|active|1
127.0.0.1 disabled.example|inactive|0
# ignored comment

[list:domain]
allow.example|allow|1
CONF
printf '127.0.0.1 existing.example\n' > "$TMP/pg/local/hosts"
PG="$TMP/pg" CONF="$TMP/settings.conf" sh -c '. "$1/util.sh"; pg_migrate_lists; pg_migrate_lists' sh "$HERE"
F="$TMP/pg/local/hosts"
grep -Fxq '127.0.0.1 existing.example' "$F"
grep -Fxq '0.0.0.0 enabled.example' "$F"
grep -Fxq '# disabled legacy hosts entry: 127.0.0.1 disabled.example' "$F"
test "$(grep -Fc '0.0.0.0 enabled.example' "$F")" -eq 1
test -f "$TMP/pg/cache/hosts-local-list-migrated-v1"

# A failed final write must not publish the completion marker. Fixing the blocker
# and running migration again must migrate the legacy value rather than lose it.
R="$TMP/retry"
mkdir -p "$R/pg/local" "$R/pg/cache" "$R/pg/local/hosts.migrate-write"
cat > "$R/settings.conf" <<'RETRY_CONF'
[list:hosts_local]
0.0.0.0 retry.example|must survive write failure|1
RETRY_CONF
if PG="$R/pg" CONF="$R/settings.conf" sh -c '. "$1/util.sh"; pg_migrate_lists' sh "$HERE" 2>/dev/null; then :; fi
test ! -f "$R/pg/cache/hosts-local-list-migrated-v1"
rmdir "$R/pg/local/hosts.migrate-write"
PG="$R/pg" CONF="$R/settings.conf" sh -c '. "$1/util.sh"; pg_migrate_lists; pg_migrate_lists' sh "$HERE"
grep -Fxq '0.0.0.0 retry.example' "$R/pg/local/hosts"
test -f "$R/pg/cache/hosts-local-list-migrated-v1"
test "$(grep -Fc '0.0.0.0 retry.example' "$R/pg/local/hosts")" -eq 1
echo 'FX legacy local hosts migration regression: PASS (incl. failed-write retry)'
