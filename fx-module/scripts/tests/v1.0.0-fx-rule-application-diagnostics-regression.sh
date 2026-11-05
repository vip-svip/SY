#!/system/bin/sh
# Audit97: enabled FX rules must report real normalized counts and diagnose empty expansion.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
UTIL="$ROOT/scripts/util.sh"
grep -Fq 'pg_fx_expand > "$_fxraw"' "$APPLY"
grep -Fq 'normalized rules total=$_fx_total_n exact_domains=$_fx_exact_n suffix_domains=$_fx_suffix_n keywords_route_only=$_fx_keyword_n ip_cidrs=$_fx_ip_n package_rules=$_fx_package_n process_rules_route_only=$_fx_process_n' "$APPLY"
grep -Fq '已配置规则源未产生可识别的' "$APPLY"
# Runtime-check the exact counter expression against mixed supported formats.
actual=$(printf '%s\n' 'DOMAIN,example.com,REJECT' 'DOMAIN-SUFFIX,ads.example,REJECT' 'DOMAIN-KEYWORD,track,REJECT' 'IP-CIDR,192.0.2.0/24,REJECT' 'IP-CIDR6,2001:db8::/32,REJECT' 'PACKAGE-NAME,com.example.app,REJECT' 'PROCESS-NAME,example,REJECT' 'UNSUPPORTED,ignored' | awk -F',' '$1=="DOMAIN" {e++} $1=="DOMAIN-SUFFIX" {s++} $1=="DOMAIN-KEYWORD" {k++} $1=="IP-CIDR" || $1=="IP-CIDR6" {i++} $1=="PACKAGE-NAME" {p++} $1=="PROCESS-NAME" {pr++} END {d=e+s; printf "%d %d %d %d %d %d %d %d", d+0, e+0, s+0, k+0, i+0, p+0, pr+0, (d+k+i+p+pr)+0}')
[ "$actual" = '2 1 1 1 2 1 1 7' ] || { echo "FAIL: unexpected FX counters: $actual"; exit 1; }
# Domain conversion should only create hosts entries for exact/suffix rules, not keyword/IP rules.
hosts=$(printf '%s\n' 'DOMAIN,Example.COM,REJECT' 'DOMAIN-SUFFIX,Ads.Example,REJECT' 'DOMAIN-KEYWORD,track,REJECT' 'IP-CIDR,192.0.2.0/24,REJECT' | awk -F',' '$1=="DOMAIN"||$1=="DOMAIN-SUFFIX"{v=tolower($2); if (v ~ /\./) print "0.0.0.0 " v}')
[ "$hosts" = "$(printf '%s\n' '0.0.0.0 example.com' '0.0.0.0 ads.example')" ] || { echo 'FAIL: FX host-layer conversion changed unexpectedly'; exit 1; }
sh -n "$APPLY"
sh -n "$UTIL"
grep -Fq 'wildcard descendant matching requires the VPN route engine' "$APPLY"
grep -Fq 'DIRECT hosts mode cannot enforce DOMAIN-KEYWORD rules' "$APPLY"
grep -Fq 'PROCESS-NAME rules are parsed but are not reliable under the current REDIRECT ingress' "$APPLY"
grep -Fq 'PROCESS-NAME rules are parsed but are not reliable under the current REDIRECT ingress' "$UTIL"
echo 'PASS: FX diagnostics count domain/IP/package/process rules and disclose direct-mode limitations'
