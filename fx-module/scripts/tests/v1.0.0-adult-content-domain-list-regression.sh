#!/system/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CONF="$ROOT/scripts/default.conf"
LIST="$ROOT/rulefiles/AdultContent_Domains.txt"
grep -Fq 'builtin://AdultContent_Domains.txt|【成人内容网站阻止】独立域名清单（默认关闭；与成人广告域名分离）|0' "$CONF" || { echo 'FAIL: content-site block list must be opt-in' >&2; exit 1; }
grep -Fq '0.0.0.0 pornhub.com' "$LIST" || { echo 'FAIL: seed domain missing' >&2; exit 1; }
grep -Fq 'AdultSite_AdHosts.txt' "$CONF" || { echo 'FAIL: adult ad network list missing' >&2; exit 1; }
if grep -Eiq '(^|[[:space:]])(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+(pornhub\.com|xvideos\.com|xnxx\.com)' "$ROOT/rulefiles/AdultSite_AdHosts.txt"; then echo 'FAIL: content roots mixed into ad network list' >&2; exit 1; fi
echo 'Adult content domain list separation regression: PASS'
