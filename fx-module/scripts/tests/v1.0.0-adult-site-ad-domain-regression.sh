#!/system/bin/sh
# Adult ad-network rules are enabled in their own category; legacy catch-all ad/tracking and user blacklist remain separate and off.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
RULES="$ROOT/rulefiles/privacy_ad_domains.txt"
awk '/^\[list:block\][[:space:]]*$/{s=1;next} /^\[/{s=0} s && $0 !~ /^[[:space:]]*#/ && NF {bad=1} END{exit bad}' "$CONF" || { echo 'FAIL: user blacklist must be empty' >&2; exit 1; }
grep -Fq 'builtin://privacy_ad_domains|【通用广告与追踪域名】内置域名补充清单（默认关闭）|0' "$CONF" || { echo 'FAIL: legacy catch-all ad-network set must remain separate and opt-in' >&2; exit 1; }
grep -Fq 'builtin://AdultSite_AdHosts.txt|【成人广告网络域名】内置成人广告供应商/弹窗域名（不屏蔽成人内容站根域）|1' "$CONF" || { echo 'FAIL: focused adult ad-network set should be enabled' >&2; exit 1; }
grep -Fq 'https://raw.githubusercontent.com/Ultimate-Hosts-Blacklist/yoyo.org_domains/master/domains.list|【广告服务器域名】yoyo.org综合域名补充（仅域名子集；按需启用）|1' "$CONF" || { echo 'FAIL: upstream ad-server domain coverage should be active' >&2; exit 1; }
for d in exoclick.com trafficjunky.net juicyads.com popads.net propellerads.com hilltopads.net trafficstars.com ero-advertising.com adsterra.com adnium.com plugrush.com; do
  grep -Eq "^0\\.0\\.0\\.0[[:space:]]+$d$" "$RULES" || { echo "FAIL: missing preserved adult-site ad domain: $d" >&2; exit 1; }
done
if grep -Eq '^0\.0\.0\.0[[:space:]]+acquire\.lupplovh\.cc$' "$RULES"; then
  echo 'FAIL: site hostname from the screenshot must not be blocked wholesale' >&2
  exit 1
fi
echo 'PASS: focused adult ad networks enabled separately; adult content roots and user blacklist remain unblocked'
