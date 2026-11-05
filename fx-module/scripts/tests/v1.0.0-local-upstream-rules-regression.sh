#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
UTIL="$ROOT/scripts/util.sh"
VPNRULE="$ROOT/scripts/vpnrule.sh"
for pair in \
  'builtin://AdultSite_Elements_EasyList.txt|【成人网站广告元素】' \
  'builtin://AdultSite_AdServers.txt|【成人广告服务器请求】' \
  'builtin://AdultSite_Allowlist.txt|【成人站点资源白名单】' \
  'builtin://AdultSite_AdServersPopup.txt|【成人广告服务器弹窗】' \
  'builtin://AdultSite_SitePopup.txt|【成人网站站点弹窗】' \
  'builtin://AdultSite_ThirdPartyPopup.txt|【成人第三方弹窗】' \
  'builtin://AdultSite_RequestRules.txt|【成人网站专用请求过滤】' \
  'builtin://AdultSite_ThirdParty.txt|【成人网站第三方资源】' \
  'builtin://RunningCheese_Watermark.txt|【网页水印补充】' \
  'builtin://RunningCheese_Popup.txt|【网页浮层弹窗补充】'; do
  key=${pair%%|*}; label=${pair#*|}
  awk -F'|' -v k="$key" -v l="$label" '$1==k && index($2,l)==1 {n++} END {exit n!=1}' "$CONF" || { echo "FAIL: missing or duplicate local rule $key" >&2; exit 1; }
  file=${key#builtin://}
  [ -s "$ROOT/rulefiles/$file" ] || { echo "FAIL: local rule data missing $file" >&2; exit 1; }
done
# Web cosmetic and contextual request rules must not leak into DNS route rules.
grep -Fq 'AdultSite_Elements_EasyList.txt' "$ROOT/mitm/cosmetic.go"
grep -Fq 'AdultSite_AdServers.txt' "$ROOT/mitm/networkfilter.go"
grep -Fq 'AdultSite_Elements_EasyList.txt' "$VPNRULE"
grep -Fq 'AdultSite_AdServers.txt' "$VPNRULE"
grep -Fq 'AdultSite_RequestRules.txt' "$ROOT/mitm/networkfilter.go"
grep -Fq 'AdultSite_ThirdParty.txt' "$ROOT/mitm/networkfilter.go"
grep -Fq 'builtin_local_upstream_rules_v1.done' "$UTIL"
# Keep adult content site roots out of the host-only deny list.
! grep -Eiq '^[[:space:]]*(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+(pornhub\.com|xvideos\.com|xnxx\.com|redtube\.com)([[:space:]]|$)' "$ROOT/rulefiles/AdultSite_AdHosts.txt"
echo 'PASS: Chinese-labeled local upstream rules exist, request rules load separately, and adult content roots are not DNS-blocked'
