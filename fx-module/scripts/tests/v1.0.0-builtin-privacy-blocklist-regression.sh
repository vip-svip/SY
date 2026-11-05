#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
UTIL="$ROOT/scripts/util.sh"
LEGACY="$ROOT/rulefiles/privacy_ad_domains.txt"
[ -s "$LEGACY" ] || { echo 'FAIL: preserved legacy domains missing from opt-in ruleset' >&2; exit 1; }
awk '/^\[list:block\][[:space:]]*$/{s=1;next} /^\[/{s=0} s && $0 !~ /^[[:space:]]*#/ && NF {bad=1} END{exit bad}' "$CONF" || { echo 'FAIL: default blacklist is not empty' >&2; exit 1; }
grep -Fq 'builtin://privacy_ad_domains|【通用广告与追踪域名】内置域名补充清单（默认关闭）|0' "$CONF" || { echo 'FAIL: legacy domains are not an opt-in rule set' >&2; exit 1; }
grep -Fq 'https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Adblock.txt|【通用网页广告】秋风 AWAvenue 广告过滤规则（默认关闭）|0' "$CONF" || { echo 'FAIL: corrected AWAvenue ruleset must be present but disabled by default' >&2; exit 1; }
grep -Fq 'https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt|【综合广告域名】1Hosts Lite 域名清单（默认关闭）|0' "$CONF" || { echo 'FAIL: historical AdGuard ruleset missing/incorrect default' >&2; exit 1; }
grep -Fq 'https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt|【综合广告与追踪】HaGeZi Multi PRO 清单（默认关闭）|0' "$CONF" || { echo 'FAIL: historical HaGeZi ruleset missing/incorrect default' >&2; exit 1; }
awk '/^\[list:rule\]/{s=1;next} /^\[/{s=0} s && /NoAppDownload.txt/ {a=1} s && /Adblock_Watermark.txt/ {b=1} END{exit !(a&&b)}' "$CONF"
if awk '/^\[list:fx\]/{s=1;next} /^\[/{s=0} s && /NoAppDownload.txt|Adblock_Watermark.txt/ {found=1} END{exit !found}' "$CONF"; then echo 'FAIL: cosmetic rules leaked into FX rules' >&2; exit 1; fi
grep -Fq 'migrate-block-empty-v1.done' "$UTIL"
! grep -Fq 'incremental privacy/ad blocklist v3 installed' "$UTIL"
! grep -Eq '^[[:space:]]*[A-Za-z0-9.-]*porn[A-Za-z0-9.-]*\|' "$CONF"
echo 'PASS: blacklist is empty; legacy domains are preserved in a disabled standalone ruleset'
