#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-rule-migration.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/pg/cache" "$T/pg/local"
# Simulate a user who already passed the old default-subscription disable migration.
: > "$T/pg/cache/migrate-1108-off.done"
export T
cat > "$T/settings.conf" <<'__CONF__'
fx=0
vpn_mode=direct
[list:rule]
https://user.example/rules.txt|用户原有订阅|1
https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Clash-classical.yaml|旧版秋风订阅|1
https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt|旧版 HaGeZi PRO|1
https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt|AdGuard Hostlists Registry filter_24（按需启用；默认关闭）|0
builtin://existing-custom.txt|用户原有内置规则|0
builtin://AdultSite_AdHosts.txt|成人网站广告网络域名（仅广告供应商，默认关闭）|0
[list:block]
old-ad.example|旧黑名单域名|1
0.0.0.0 old-track.example|旧黑名单 IP 格式行|1
off.example|旧停用项|0
[list:fx]
builtin://NoAppDownload.txt|旧版错误放入 FX 的开屏规则|0
builtin://Adblock_Watermark.txt|旧版错误放入 FX 的水印规则|1
builtin://AdultSite_AdPopup.txt|旧版错误放入 FX 的成人广告元素规则|1
builtin://Adblock_Warning_Removal.txt|旧版错误放入 FX 的反广告提示规则|1
__CONF__
PG="$T/pg" CONF="$T/settings.conf" MODDIR="$ROOT" sh -c '
  . "$1/scripts/util.sh"
  pg_migrate_lists
  pg_migrate_lists
  rules=$(pg_list rule)
  printf "%s\n" "$rules" | grep -Fq "https://user.example/rules.txt|用户原有订阅|1"
  printf "%s\n" "$rules" | grep -Fq "builtin://existing-custom.txt|用户原有内置规则|0"
  printf "%s\n" "$rules" | grep -Fq "builtin://NoAppDownload.txt|"
  printf "%s\n" "$rules" | grep -Fq "builtin://Adblock_Watermark.txt|"
  printf "%s\n" "$rules" | grep -Fq "builtin://AdultSite_AdPopup.txt|"
  printf "%s\n" "$rules" | grep -Fq "builtin://Adblock_Warning_Removal.txt|"
  printf "%s\n" "$rules" | grep -Fq "builtin://AdultSite_AdHosts.txt|"
  printf "%s\n" "$rules" | grep -Fq "builtin://AdultSite_AdHosts.txt|【成人广告网络域名】内置成人广告供应商/弹窗域名（不屏蔽成人内容站根域）|1"
  [ "$(printf "%s\n" "$rules" | grep -Fc "builtin://AdultSite_AdHosts.txt|")" -eq 1 ]
  # The local-source migration must not silently delete unrelated user sources.
  printf "%s\n" "$rules" | grep -Fq "https://user.example/rules.txt|用户原有订阅|1"
  # Adult and watermark/app-prompt rules are bundled locally; redundant network copies stay off.
  for url in \
    "https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt" \
    "https://cdn.jsdelivr.net/gh/Noyllopa/NoAppDownload@master/NoAppDownload.txt" \
    "https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Watermark.txt" \
    "https://raw.githubusercontent.com/runningcheese/RunningCheese-Firefox/master/Restore/Adblock_Popup.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_hide.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_allowlist.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_adservers_popup.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_specific_block_popup.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty.txt" \
    "https://raw.githubusercontent.com/easylist/easylist/master/easylist_adult/adult_thirdparty_popup.txt"; do
    line=$(printf "%s\n" "$rules" | grep -F "$url|" || true)
    [ -n "$line" ] || { echo "FAIL: local source migration removed the online backup row: $url" >&2; exit 1; }
    [ "${line##*|}" = 0 ] || { echo "FAIL: redundant online source remains enabled beside its local snapshot: $url" >&2; exit 1; }
    [ "$(printf "%s\n" "$rules" | grep -Fc "$url|")" -eq 1 ] || { echo "FAIL: duplicate online backup row: $url" >&2; exit 1; }
  done
  for key in \
    "builtin://NoAppDownload.txt" "builtin://RunningCheese_Watermark.txt" \
    "builtin://RunningCheese_Popup.txt" "builtin://AdultSite_Elements_EasyList.txt" \
    "builtin://AdultSite_AdServers.txt" "builtin://AdultSite_Allowlist.txt" \
    "builtin://AdultSite_AdServersPopup.txt" "builtin://AdultSite_SitePopup.txt" \
    "builtin://AdultSite_ThirdPartyPopup.txt" "builtin://AdultSite_RequestRules.txt" \
    "builtin://AdultSite_ThirdParty.txt"; do
    line=$(printf "%s\n" "$rules" | grep -F "$key|" || true)
    [ -n "$line" ] || { echo "FAIL: missing local packaged source after migration: $key" >&2; exit 1; }
    [ "${line##*|}" = 1 ] || { echo "FAIL: local packaged source unexpectedly disabled: $key" >&2; exit 1; }
  done
  printf "%s\n" "$rules" | grep -Fq "builtin://privacy_ad_domains|"
  awa="https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt"
  printf "%s\n" "$rules" | grep -Fq "$awa|秋风广告规则（官方 Adblock 格式；默认关闭）|1"
  ! printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Clash-classical.yaml|"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/rules.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/lingeringsound/10007_auto/master/all|"
  printf "%s\n" "$rules" | grep -Fq "https://gitlab.com/andryou/block/raw/master/chibi|"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://easylist-downloads.adblockplus.org/easylist.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://easylist-downloads.adblockplus.org/easyprivacy.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://easylist-downloads.adblockplus.org/easylistchina.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt|EasyList 反广告拦截提示规则（兼容子集；默认开启）|1"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt|HaGeZi Multi PRO（Adblock 格式；默认关闭）|1"
  printf "%s\n" "$rules" | grep -Fq "https://filters.adtidy.org/extension/ublock/filters/14.txt|AdGuard Annoyances 弹窗/烦人元素规则（引擎兼容子集；默认开启）|1"
  printf "%s\n" "$rules" | grep -Fq "https://filters.adtidy.org/extension/ublock/filters/224.txt|AdGuard 中文网站广告规则（引擎兼容子集；默认开启）|1"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-mobile.txt|uBlock 移动网页广告规则（标准 CSS/域名子集；默认开启）|1"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt|uBlock Other Annoyances（标准 CSS/域名子集；高级脚本规则不执行；默认开启）|1"
  printf "%s\n" "$rules" | grep -Fq "https://easylist.to/easylist/fanboy-annoyance.txt|Fanboy Annoyance 综合弹窗/烦人元素规则（兼容子集；默认关闭）|0"
  printf "%s\n" "$rules" | grep -Fq "https://easylist.to/easylist/fanboy-social.txt|Fanboy Social 社交组件规则（兼容子集；默认关闭）|0"
  printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/yoyo.org_domains/master/domains.list|Ultimate Hosts yoyo.org 广告服务器域名（不屏蔽成人内容站点；默认开启）|1"
  ! printf "%s\n" "$rules" | grep -Fq "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt|"
  printf "%s\n" "$rules" | grep -Fq "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt|1Hosts Lite（AdGuard Hostlists Registry；默认关闭）|0"
  # Pre-existing AWAvenue and HaGeZi selections stay enabled; newly-added catalogs must be off.
  for url in \
    "https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/rules.txt" \
    "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt" \
    "https://raw.githubusercontent.com/lingeringsound/10007_auto/master/all" \
    "https://gitlab.com/andryou/block/raw/master/chibi" \
    "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt" \
    "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt" \
    "https://easylist-downloads.adblockplus.org/easylist.txt" \
    "https://easylist-downloads.adblockplus.org/easyprivacy.txt" \
    "https://easylist-downloads.adblockplus.org/easylistchina.txt" \
    "https://raw.githubusercontent.com/Noyllopa/NoAppDownload/master/NoAppDownload.txt" \
    "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt"; do
    line=$(printf "%s\n" "$rules" | grep -F "$url|" || true)
    [ -n "$line" ] || { echo "FAIL: missing catalog row: $url" >&2; exit 1; }
    [ "${line##*|}" = 0 ] || { echo "FAIL: new catalog source not default-off: $url" >&2; exit 1; }
    [ "$(printf "%s\n" "$rules" | grep -Fc "$url|")" -eq 1 ] || { echo "FAIL: duplicate catalog row: $url" >&2; exit 1; }
  done
  for spec in \
    "https://filters.adtidy.org/extension/ublock/filters/14.txt|1" \
    "https://filters.adtidy.org/extension/ublock/filters/224.txt|1" \
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters-mobile.txt|1" \
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt|1" \
    "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt|1" \
    "https://easylist.to/easylist/fanboy-annoyance.txt|0" \
    "https://easylist.to/easylist/fanboy-social.txt|0" \
    "https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/yoyo.org_domains/master/domains.list|1"; do
    url=${spec%|*}; expected=${spec##*|}
    line=$(printf "%s\n" "$rules" | grep -F "$url|" || true)
    [ -n "$line" ] || { echo "FAIL: missing v4 source: $url" >&2; exit 1; }
    [ "${line##*|}" = "$expected" ] || { echo "FAIL: unexpected default state for v4 source: $url" >&2; exit 1; }
    [ "$(printf "%s\n" "$rules" | grep -Fc "$url|")" -eq 1 ] || { echo "FAIL: duplicate v4 source: $url" >&2; exit 1; }
  done
  fxrows=$(pg_list fx)
  ! printf "%s\n" "$fxrows" | grep -Eq "NoAppDownload|Adblock_Watermark|AdultSite_AdPopup|Adblock_Warning_Removal|AdultSite_AdHosts"
  # The old blacklist must have no active data rows after migration.
  if pg_list block | grep -v "^[[:space:]]*#" | grep -v "^[[:space:]]*$" | grep -q .; then echo "FAIL: blacklist is not empty" >&2; exit 1; fi
  [ -f "$PG/rulefiles-user/privacy_ad_domains.txt" ]
  grep -Fq "0.0.0.0 old-ad.example" "$PG/rulefiles-user/privacy_ad_domains.txt"
  grep -Fq "0.0.0.0 old-track.example" "$PG/rulefiles-user/privacy_ad_domains.txt"
  [ "$(grep -Fc "https://user.example/rules.txt|用户原有订阅|1" "$T/settings.conf")" -eq 1 ]
  [ "$(grep -Fc "builtin://NoAppDownload.txt|" "$T/settings.conf")" -eq 1 ]
  [ "$(grep -Fc "https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt|" "$T/settings.conf")" -eq 1 ]
' sh "$ROOT"
echo 'PASS: migration preserves user state, adds targeted upstream rules enabled, keeps broader sources opt-in and anti-fraud sources separate'
