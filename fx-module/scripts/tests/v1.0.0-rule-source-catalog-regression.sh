#!/system/bin/sh
# Verifies both first-install catalog and upgrade migration contain the independently
# selectable historical sources, enabling targeted cosmetic sources, and keeping broad optional lists off.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
UTIL="$ROOT/scripts/util.sh"
SOURCES='https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt
https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/rules.txt
https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt
https://raw.githubusercontent.com/lingeringsound/10007_auto/master/all
https://gitlab.com/andryou/block/raw/master/chibi
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt
https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt
https://easylist-downloads.adblockplus.org/easylist.txt
https://easylist-downloads.adblockplus.org/easyprivacy.txt
https://easylist-downloads.adblockplus.org/easylistchina.txt
https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt
https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt'
printf '%s\n' "$SOURCES" | while IFS= read -r url; do
  [ -n "$url" ] || continue
  line=$(awk -F'|' -v u="$url" '$1==u {print; n++} END {if(n!=1) exit 1}' "$CONF") || { echo "FAIL: missing or duplicate default source: $url" >&2; exit 1; }
  [ "$(printf '%s\n' "$line" | awk -F'|' '{print $3}')" = 0 ] || { echo "FAIL: remote source must be default-off: $url" >&2; exit 1; }
done

V4_ON='https://filters.adtidy.org/extension/ublock/filters/14.txt
https://filters.adtidy.org/extension/ublock/filters/224.txt
https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-mobile.txt
https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt
https://easylist-downloads.adblockplus.org/antiadblockfilters.txt
https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/yoyo.org_domains/master/domains.list'
printf '%s\n' "$V4_ON" | while IFS= read -r url; do
  line=$(awk -F'|' -v u="$url" '$1==u {print; n++} END {if(n!=1) exit 1}' "$CONF") || { echo "FAIL: missing or duplicate targeted upstream source: $url" >&2; exit 1; }
  [ "$(printf '%s\n' "$line" | awk -F'|' '{print $3}')" = 1 ] || { echo "FAIL: targeted upstream source must be enabled for better default coverage: $url" >&2; exit 1; }
done
V4_OFF='https://easylist.to/easylist/fanboy-annoyance.txt
https://easylist.to/easylist/fanboy-social.txt'
# Yokoffing Adult Annoyances includes many non-ad site-content selectors and advanced syntax;
# it is deliberately not promoted to an enabled default or represented as an offline snapshot.
ADULT_ONLINE='https://raw.githubusercontent.com/yokoffing/filterlists/main/adult_annoyance_list.txt'
line=$(awk -F'|' -v u="$ADULT_ONLINE" '$1==u {print; n++} END {if(n!=1) exit 1}' "$CONF") || { echo "FAIL: optional Adult Annoyances source missing or duplicated" >&2; exit 1; }
[ "$(printf '%s\n' "$line" | awk -F'|' '{print $3}')" = 0 ] || { echo "FAIL: non-local Adult Annoyances source should remain opt-in" >&2; exit 1; }
printf '%s\n' "$V4_OFF" | while IFS= read -r url; do
  line=$(awk -F'|' -v u="$url" '$1==u {print; n++} END {if(n!=1) exit 1}' "$CONF") || { echo "FAIL: missing or duplicate optional upstream source: $url" >&2; exit 1; }
  [ "$(printf '%s\n' "$line" | awk -F'|' '{print $3}')" = 0 ] || { echo "FAIL: broad optional source should remain separately opt-in: $url" >&2; exit 1; }
done
# The upstream config belongs only to [list:rule], never the FX anti-fraud list.
awk '
  /^\[list:rule\][[:space:]]*$/ {section="rule"; next}
  /^\[list:fx\][[:space:]]*$/ {section="fx"; next}
  /^\[/ {section=""}
  section=="rule" && /^(fxfile:\/\/|builtin:\/\/)/ {if ($0 ~ /fxfile:\/\//) bad=1}
  section=="fx" && /^(https?:\/\/|builtin:\/\/|.*easylist|.*AdAway|.*AWAvenue)/ {bad=1}
  END {if(bad) exit 1}
' "$CONF" || { echo 'FAIL: rule sources and FX sources are mixed' >&2; exit 1; }
# Adult-site upstream URLs are now offline snapshots; redundant remote copies are
# separately named, default-off backups while local Chinese-labeled files are on.
ADULT_REMOTE='https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt
https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt'
printf '%s\n' "$ADULT_REMOTE" | while IFS= read -r url; do
  line=$(awk -F'|' -v u="$url" '$1==u {print; n++} END {if(n!=1) exit 1}' "$CONF") || { echo "FAIL: missing or duplicate adult backup source: $url" >&2; exit 1; }
  [ "$(printf '%s\n' "$line" | awk -F'|' '{print $3}')" = 0 ] || { echo "FAIL: duplicate remote adult source must be off when its snapshot is bundled: $url" >&2; exit 1; }
  printf '%s\n' "$line" | grep -Eq '\|【在线(备用|更新备用)】' || { echo "FAIL: remote adult copy needs a Chinese backup label: $url" >&2; exit 1; }
done
for local_rule in \
  'builtin://AdultSite_Elements_EasyList.txt|【成人网站广告元素】' \
  'builtin://AdultSite_AdServers.txt|【成人广告服务器请求】' \
  'builtin://AdultSite_Allowlist.txt|【成人站点资源白名单】' \
  'builtin://AdultSite_AdServersPopup.txt|【成人广告服务器弹窗】' \
  'builtin://AdultSite_SitePopup.txt|【成人网站站点弹窗】' \
  'builtin://AdultSite_ThirdPartyPopup.txt|【成人第三方弹窗】' \
  'builtin://AdultSite_RequestRules.txt|【成人网站专用请求过滤】' \
  'builtin://AdultSite_ThirdParty.txt|【成人网站第三方资源】'; do
  key=${local_rule%%|*}; label=${local_rule#*|}
  awk -F'|' -v k="$key" -v l="$label" '$1==k && index($2,l)==1 && $3==1 {n++} END {exit n!=1}' "$CONF" || { echo "FAIL: missing, duplicate, disabled, or misnamed bundled adult source: $key" >&2; exit 1; }
done
# FX anti-fraud list stays separate from general adult/ad filtering.
# Upgrade migrations add v4 upstream sources once and fix obsolete URLs.
grep -Fq 'migrate-rule-starters-v3.done' "$UTIL"
grep -Fq 'migrate-rule-catalog-v4.done' "$UTIL"
grep -Fq 'migrate-antiadblock-upstream-v6.done' "$UTIL"
grep -Fq 'migrate: rule catalog v4 upstream coverage sources registered' "$UTIL"
grep -Fq 'AWAvenue-Ads-Rule-Adblock.txt' "$UTIL"
! grep -Fq 'AWAvenue-Ads-Rule-Clash-classical.yaml|秋风广告规则（用户指定规则源；默认关闭）|0' "$CONF"
grep -Fq 'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt|【通用网页广告】uBlock Origin完整网页过滤清单（大清单；默认关闭，可单独开启）|0' "$CONF" || { echo 'FAIL: optional complete uBlock filter source missing from Chinese catalog' >&2; exit 1; }
grep -Fq 'migrate-rule-catalog-v8.done' "$UTIL" || { echo 'FAIL: full uBlock source lacks upgrade migration' >&2; exit 1; }
grep -Fq 'rule_catalog_chinese_labels_v2.done' "$UTIL" || { echo 'FAIL: old installs lack Chinese rule-purpose label migration' >&2; exit 1; }
echo 'PASS: expanded upstream catalog, targeted compatible sources default-on, broad optional sources default-off, FX anti-fraud stays separate'


