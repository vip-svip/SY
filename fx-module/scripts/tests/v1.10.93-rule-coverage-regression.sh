#!/system/bin/sh
# Historical coverage regression updated for the intended separation:
# advertising domains live in an optional rule set; [list:block] stays empty.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
RULEFILE="$ROOT/rulefiles/privacy_ad_domains.txt"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -s "$CONF" ] || fail "default.conf missing"
[ -s "$RULEFILE" ] || fail "optional ad/tracking rule file missing"
awk '
  /^\[list:block\]$/ { inblock=1; next }
  /^\[/ && inblock { inblock=0 }
  inblock && /^[[:space:]]*#/ { next }
  inblock && NF { print }
' "$CONF" > "${TMPDIR:-/tmp}/pg-rules-$$"
trap 'rm -f "${TMPDIR:-/tmp}/pg-rules-$$"' EXIT HUP INT TERM
[ ! -s "${TMPDIR:-/tmp}/pg-rules-$$" ] || fail "blacklist must remain empty"
grep -Fq 'builtin://privacy_ad_domains|【通用广告与追踪域名】内置域名补充清单（默认关闭）|0' "$CONF" || fail "optional ruleset missing or not default-off"
check_enabled() {
  domain=$1
  grep -E "^0\.0\.0\.0[[:space:]]+${domain}$|^127\.0\.0\.1[[:space:]]+${domain}$|^${domain}$" "$RULEFILE" >/dev/null 2>&1 || fail "missing preserved optional rule: $domain"
}
# Domestic ad/launch-screen and tracking domains from the preserved user rules.
check_enabled ad.xiaomi.com
check_enabled adsfs.oppomobile.com
check_enabled doubleclick.net
check_enabled analytics.google.com
check_enabled appsflyer.com
check_enabled pixel.quantserve.com
# Adult-site ad networks only; do not claim to block the sites themselves.
check_enabled exoclick.com
check_enabled trafficjunky.net
check_enabled juicyads.com
if grep -Eiq 'DNS/Hosts.{0,20}(can|可以).{0,10}(remove|去除).{0,10}watermark|DNS/Hosts.{0,20}去除水印' "$CONF"; then
  fail "unsafe claim that DNS/hosts removes visual watermarks"
fi
awk '
 /^[[:space:]]*#/ || /^[[:space:]]*$/ {next}
 NF!=2 || $1!~/^(0\.0\.0\.0|127\.0\.0\.1|::1)$/ || $2 !~ /^[A-Za-z0-9._-]+$/ {print "malformed optional host rule: "$0 > "/dev/stderr"; bad=1}
 END {exit bad}
' "$RULEFILE" || fail "malformed optional rule file"
echo "PASS: ad/tracking coverage is retained in the opt-in ruleset while blacklist remains empty"
