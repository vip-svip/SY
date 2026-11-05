#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BOOT="$ROOT/post-fs-data.sh"; UTIL="$ROOT/scripts/util.sh"; APPLY="$ROOT/scripts/apply.sh"
if grep -Eq '_AD_MASTER|\(get ad_protection_master' "$BOOT"; then echo 'FAIL: early boot still reads removed page master' >&2; exit 1; fi
grep -Fq '_HOSTS_BLOCK_EFFECTIVE=$_HOSTS_BLOCK' "$BOOT"
grep -Fq '_FX_MASTER=$(get fx 0)' "$BOOT"
grep -Fq '_HOSTS_MODE=$(cat "$PG/cache/hosts-mode"' "$BOOT"
grep -Fq 'foreign mount at $HOSTS_TARGET preserved' "$BOOT"
grep -Fq '_auto_hosts_rules=1' "$APPLY"
grep -Fq 'pg_list_enabled "$_asect"' "$APPLY"
if grep -Fq 'ad_protection_master=' "$ROOT/scripts/default.conf"; then echo 'FAIL: legacy master remains in defaults' >&2; exit 1; fi
sh -n "$BOOT"; sh -n "$UTIL"; sh -n "$APPLY"
echo 'PASS: early boot derives hosts mount from active rows and preserves foreign mounts'
