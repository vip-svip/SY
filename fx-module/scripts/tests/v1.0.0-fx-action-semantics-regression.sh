#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
UTIL="$ROOT/scripts/util.sh"
APPLY="$ROOT/scripts/apply.sh"
SRC="$ROOT/fxrules/anti_fraud_96110.txt"

# All three consumers must respect an explicit DIRECT/PASS-style action instead of
# forcing every matching row into an unconditional block. Actionless legacy list rows
# retain the historical FX deny-list default.
grep -Fq 'toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP"' "$APPLY"
grep -Fq 'action!="" && action!="REJECT" && action!="BLOCK" && action!="DROP"' "$UTIL"
grep -Fq 'toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP"' "$APPLY"

# Exercise the same AWK predicates: DIRECT must never become a hosts or firewall block.
domains=$(printf '%s\n' \
  'DOMAIN,block.example,REJECT' \
  'DOMAIN,allow.example,DIRECT' \
  'DOMAIN-SUFFIX,legacy.example' \
  'DOMAIN-SUFFIX,drop.example,REJECT-DROP' \
  'DOMAIN-SUFFIX,pass.example,PASS' |
  awk -F',' '($1=="DOMAIN"||$1=="DOMAIN-SUFFIX") && (toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP") {print "0.0.0.0 " tolower($2)}')
[ "$domains" = "$(printf '%s\n' '0.0.0.0 block.example' '0.0.0.0 legacy.example' '0.0.0.0 drop.example')" ] || { echo "FAIL: FX hosts action mismatch: $domains" >&2; exit 1; }
ips=$(printf '%s\n' \
  'IP-CIDR,192.0.2.0/24,REJECT' \
  'IP-CIDR,198.51.100.0/24,DIRECT' \
  'IP-CIDR6,2001:db8::/32' \
  'IP-CIDR6,2001:db8:1::/48,PASS' |
  awk -F',' '($1=="IP-CIDR"||$1=="IP-CIDR6") && (toupper($3)==""||toupper($3)=="REJECT"||toupper($3)=="BLOCK"||toupper($3)=="DROP"||toupper($3)=="DENY"||toupper($3)=="REJECT-DROP") {print $2}')
[ "$ips" = "$(printf '%s\n' '192.0.2.0/24' '2001:db8::/32')" ] || { echo "FAIL: FX IP action mismatch: $ips" >&2; exit 1; }

# URL rule normalization preserves explicit actions and applies REJECT only when omitted.
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-action.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache"
cat > "$T/remote.txt" <<'__RULES__'
DOMAIN,allow.example,DIRECT
DOMAIN,block.example
DOMAIN-SUFFIX,pass.example,PASS
IP-CIDR,198.51.100.0/24,DIRECT
IP-CIDR,192.0.2.0/24
IP-CIDR,203.0.113.0/24,no-resolve
0.0.0.0 host.example
legacy.example
PACKAGE-NAME,com.example.app,REJECT
__RULES__
PG="$T/pg" MODDIR="$ROOT" CONF="$T/pg/settings.conf" export PG MODDIR CONF
. "$UTIL"
pg_list_enabled() { printf '%s\n' 'https://rules.example/fx.txt'; }
pg_fetch() { cp "$T/remote.txt" "$2"; }
pg_log() { :; }
OUT=$(pg_fx_expand)
printf '%s\n' "$OUT" | grep -Fxq 'DOMAIN,allow.example,DIRECT'
printf '%s\n' "$OUT" | grep -Fxq 'DOMAIN,block.example,REJECT'
printf '%s\n' "$OUT" | grep -Fxq 'DOMAIN-SUFFIX,pass.example,PASS'
printf '%s\n' "$OUT" | grep -Fxq 'IP-CIDR,198.51.100.0/24,DIRECT'
printf '%s\n' "$OUT" | grep -Fxq 'IP-CIDR,192.0.2.0/24,REJECT'
printf '%s\n' "$OUT" | grep -Fxq 'IP-CIDR,203.0.113.0/24,REJECT,no-resolve'
printf '%s\n' "$OUT" | grep -Fxq 'DOMAIN,host.example,REJECT'
printf '%s\n' "$OUT" | grep -Fxq 'DOMAIN-SUFFIX,legacy.example,REJECT'
printf '%s\n' "$OUT" | grep -Fxq 'PACKAGE-NAME,com.example.app,REJECT'

# Exercise the real FX-only hosts builder with block and pass rules mixed together.
HPG="$T/pg-hosts"
mkdir -p "$HPG/cache" "$HPG/local"
printf '127.0.0.1 localhost\n' > "$HPG/cache/system-hosts.base"
cat > "$T/host-rules.txt" <<'__HOST_RULES__'
DOMAIN,block.example,REJECT
DOMAIN,allow.example,DIRECT
DOMAIN-SUFFIX,legacy.example
DOMAIN-SUFFIX,pass.example,PASS
DOMAIN-SUFFIX,drop.example,REJECT-DROP
IP-CIDR,192.0.2.0/24,REJECT
__HOST_RULES__
PG="$HPG" CONF="$HPG/settings.conf" export PG CONF
pg_capture_system_hosts_base() { :; }
pg_fx_expand() { cat "$T/host-rules.txt"; }
pg_commit_hosts_candidate() { cp "$1" "$PG/hosts"; }
pg_get() { [ "$1" = vpn_mode ] && { echo direct; return 0; }; return 1; }
pg_log() { printf '%s\n' "$*" >> "$PG/apply.log"; }
pg_fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
pg_build_fx_hosts
HOSTS=$(cat "$HPG/hosts")
printf '%s\n' "$HOSTS" | grep -Fxq '0.0.0.0 block.example'
printf '%s\n' "$HOSTS" | grep -Fxq '0.0.0.0 legacy.example'
printf '%s\n' "$HOSTS" | grep -Fxq '0.0.0.0 drop.example'
! printf '%s\n' "$HOSTS" | grep -Eq '^0\.0\.0\.0 (allow|pass)\.example$'
grep -Fq 'FX-only hosts committed; lines=' "$HPG/apply.log"

# The compiler must interpret PASS/ACCEPT as bypass, not as an unknown proxy policy.
cat > "$T/routes.conf" <<'__ROUTES__'
fx=1
[list:fx]
DOMAIN,allow.example,PASS|pass rule|1
DOMAIN,allow2.example,ACCEPT|accept rule|1
DOMAIN,block2.example,REJECT-DROP|drop rule|1
__ROUTES__
ROUTES=$(PG="$T/pg-route" CONF="$T/routes.conf" VPNRULE_SRC="$T/routes.conf" VPNRULE_WORK="$T/work-route" sh "$ROOT/scripts/vpnrule.sh" --emit)
printf '%s\n' "$ROUTES" | grep -Fq '{"domain":["allow.example"],"outbound":"direct"}'
printf '%s\n' "$ROUTES" | grep -Fq '{"domain":["allow2.example"],"outbound":"direct"}'
printf '%s\n' "$ROUTES" | grep -Fq '{"domain":["block2.example"],"action":"reject","method":"drop"}'

# The remote-URL compiler path must also preserve action and default actionless block lists to REJECT.
cat > "$T/routes-url.conf" <<'__URL_CONF__'
fx=1
[list:fx]
https://rules.example/fx-rules.txt|remote FX blocklist|1
__URL_CONF__
mkdir -p "$T/pg-url/cache/rules"
_URL_KEY=$(printf '%s' 'https://rules.example/fx-rules.txt' | cksum | awk '{print $1}')
cat > "$T/pg-url/cache/rules/$_URL_KEY" <<'__URL_RULES__'
DOMAIN,allow.example,DIRECT
DOMAIN,block.example
DOMAIN-SUFFIX,pass.example,PASS
IP-CIDR,198.51.100.0/24,DIRECT
IP-CIDR,192.0.2.0/24
IP-CIDR,203.0.113.0/24,no-resolve
__URL_RULES__
sha256sum "$T/pg-url/cache/rules/$_URL_KEY" | awk '{print $1}' > "$T/pg-url/cache/rules/$_URL_KEY.sha256"
URL_ROUTES=$(PG="$T/pg-url" CONF="$T/routes-url.conf" VPNRULE_SRC="$T/routes-url.conf" VPNRULE_WORK="$T/work-url" sh "$ROOT/scripts/vpnrule.sh" --emit)
printf '%s\n' "$URL_ROUTES" | grep -Fq '{"domain":["allow.example"],"outbound":"direct"}'
printf '%s\n' "$URL_ROUTES" | grep -Fq '{"domain":["block.example"],"action":"reject","method":"drop"}'
printf '%s\n' "$URL_ROUTES" | grep -Fq '{"domain_suffix":["pass.example"],"outbound":"direct"}'
printf '%s\n' "$URL_ROUTES" | grep -Fq '{"ip_cidr":["198.51.100.0/24"],"outbound":"direct"}'
printf '%s\n' "$URL_ROUTES" | grep -Fq '{"ip_cidr":["192.0.2.0/24"],"action":"reject","method":"drop"}'
printf '%s\n' "$URL_ROUTES" | grep -Fq '{"ip_cidr":["203.0.113.0/24"],"action":"reject","method":"drop"}'

# An edited local copy of the built-in fxfile source must normalize actionless rows the
# same way; otherwise the route parser mistakes a match value for the policy.
mkdir -p "$T/pg-custom/fxrules-user"
cat > "$T/pg-custom/fxrules-user/anti_fraud_96110.txt" <<'__USER_FX__'
DOMAIN,default-reject.example
DOMAIN,explicit-pass.example,DIRECT
IP-CIDR,192.0.2.0/24
PACKAGE-NAME,com.example.app
__USER_FX__
cat > "$T/routes-fxfile.conf" <<'__FXFILE_CONF__'
fx=1
[list:fx]
fxfile://anti_fraud_96110|user edited FX source|1
__FXFILE_CONF__
FXFILE_ROUTES=$(PG="$T/pg-custom" CONF="$T/routes-fxfile.conf" VPNRULE_SRC="$T/routes-fxfile.conf" VPNRULE_WORK="$T/work-fxfile" sh "$ROOT/scripts/vpnrule.sh" --emit)
printf '%s\n' "$FXFILE_ROUTES" | grep -Fq '{"domain":["default-reject.example"],"action":"reject","method":"drop"}'
printf '%s\n' "$FXFILE_ROUTES" | grep -Fq '{"domain":["explicit-pass.example"],"outbound":"direct"}'
printf '%s\n' "$FXFILE_ROUTES" | grep -Fq '{"ip_cidr":["192.0.2.0/24"],"action":"reject","method":"drop"}'
printf '%s\n' "$FXFILE_ROUTES" | grep -Fq '{"package_name":["com.example.app"],"action":"reject","method":"drop"}'

# The shared expansion layer must normalize case/action/host syntax for hosts and firewall too.
mkdir -p "$T/pg-file/fxrules-user"
cat > "$T/pg-file/fxrules-user/custom.txt" <<'__LOCAL_FX__'
domain,LowerCase.Example
IP-CIDR,203.0.113.0/24,no-resolve
DOMAIN,allow-local.example,DIRECT
0.0.0.0 host-a.example host-b.example
__LOCAL_FX__
cat > "$T/local-file.conf" <<'__LOCAL_FILE_CONF__'
fx=1
[list:fx]
fxfile://custom|editable FX source|1
__LOCAL_FILE_CONF__
LOCAL_EXPANDED=$(PG="$T/pg-file" CONF="$T/local-file.conf" MODDIR="$ROOT" sh -c '. "$MODDIR/scripts/util.sh"; pg_fx_expand')
printf '%s\n' "$LOCAL_EXPANDED" | grep -Fxq 'DOMAIN,lowercase.example,REJECT'
printf '%s\n' "$LOCAL_EXPANDED" | grep -Fxq 'IP-CIDR,203.0.113.0/24,REJECT,no-resolve'
printf '%s\n' "$LOCAL_EXPANDED" | grep -Fxq 'DOMAIN,allow-local.example,DIRECT'
printf '%s\n' "$LOCAL_EXPANDED" | grep -Fxq 'DOMAIN,host-a.example,REJECT'
printf '%s\n' "$LOCAL_EXPANDED" | grep -Fxq 'DOMAIN,host-b.example,REJECT'

# Source content boundary: this dedicated list remains narrowly scoped and has no generic installer blocks.
grep -Fxq 'PACKAGE-NAME,com.hicorenational.antifraud,REJECT' "$SRC"
! grep -Eq 'PACKAGE-NAME,(com\.android\.packageinstaller|com\.oplus\.appdetail|com\.miui\.securitycenter)' "$SRC"
! grep -Eq '^DOMAIN(-SUFFIX)?,(mps\.gov\.cn|miit\.gov\.cn),REJECT' "$SRC"
sh -n "$APPLY"
sh -n "$UTIL"
echo 'PASS: FX rule actions are preserved; explicit DIRECT/PASS do not become host/IP blocks; bundle scope stays narrow'
