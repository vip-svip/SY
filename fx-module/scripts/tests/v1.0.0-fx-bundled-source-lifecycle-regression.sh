#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-bundled-source.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache" "$T/pg/local"
printf '::1 local-v6.example\n2001:db8::1 mapped-v6.example\n192.0.2.7 mapped-v4.example\nbare-local.example\n' > "$T/pg/local/hosts"
cat > "$T/settings.conf" <<'__CONF__'
fx=1
hosts_block=0
[list:rule]
[list:fx]
# Legacy config was blank; migration must register the bundled source.
__CONF__
PG="$T/pg" CONF="$T/settings.conf" MODDIR="$ROOT" sh -c '
  . "$1/scripts/util.sh"
  pg_migrate_lists
  pg_migrate_lists
  n=$(pg_list fx | grep -Fc "fxfile://anti_fraud_96110")
  [ "$n" -eq 1 ] || { echo "FAIL: FX source missing or duplicated after migration: $n" >&2; exit 1; }
  rules=$(pg_fx_expand)
  printf "%s\\n" "$rules" | grep -Fxq "DOMAIN-SUFFIX,gjfzpt.cn,REJECT"
  printf "%s\\n" "$rules" | grep -Fxq "DOMAIN,fzapph5.gjfzpt.cn,REJECT"
  printf "%s\\n" "$rules" | grep -Fxq "IP-CIDR,49.7.228.53/32,REJECT"
  printf "%s\\n" "$rules" | grep -Fxq "PACKAGE-NAME,com.hicorenational.antifraud,REJECT"
  ! printf "%s\\n" "$rules" | grep -Eq "PACKAGE-NAME,com.android.packageinstaller|PACKAGE-NAME,com.oplus.safecenter"
  pg_build_fx_hosts
  [ -s "$PG/hosts" ]
  grep -Fxq "0.0.0.0 gjfzpt.cn" "$PG/hosts"
  grep -Fxq "0.0.0.0 fzapph5.gjfzpt.cn" "$PG/hosts"
  grep -Fxq "::1 local-v6.example" "$PG/hosts"
  grep -Fxq "2001:db8::1 mapped-v6.example" "$PG/hosts"
  grep -Fxq "192.0.2.7 mapped-v4.example" "$PG/hosts"
  grep -Fxq "0.0.0.0 bare-local.example" "$PG/hosts"
  grep -Fq "FX-only hosts overlay" "$PG/hosts"
  grep -Fq "full hosts_block remains disabled" "$PG/apply.log"
  grep -Fq "wildcard descendant matching requires the VPN route engine" "$PG/apply.log"
' sh "$ROOT"
# Source must be active for the UI master switch, and FX-only mode must not depend on hosts_block.
grep -Fq 'if [ "$_hosts_block_on" = "1" ] || [ "$_fx_master_on" = "1" ]; then' "$ROOT/scripts/apply.sh"
grep -Fq 'PACKAGE-NAME,...,REJECT' "$ROOT/scripts/apply.sh"
echo 'PASS: bundled FX source migration, explicit domain/IP expansion and independent FX-only hosts path'
