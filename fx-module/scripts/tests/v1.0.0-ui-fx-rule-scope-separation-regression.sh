#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
FX="$ROOT/fxrules/anti_fraud_96110.txt"
# Rule pages intentionally have no explanatory paragraphs, per the current UI requirement.
if grep -Eq 'id="(genericRuleScopeNote|fxRuleScopeNote)"' "$HTML"; then
  echo 'FAIL: rule-page introduction note still exists' >&2; exit 1
fi
if grep -Fq '通用规则订阅（广告、域名、IP/CIDR 等）放在这里' "$HTML" || \
   grep -Fq '大陆国家反诈中心、96110/运营商监控类；不与通用订阅混放' "$HTML"; then
  echo 'FAIL: rule-page explanatory copy still exists' >&2; exit 1
fi
if grep -Fq '尚无可核验的 96110/运营商监控端点清单，未虚构条目' "$HTML"; then
  echo 'FAIL: rule page still contains explanatory placeholder copy' >&2; exit 1
fi
grep -Fq 'FX 专用规则：仅取仓库 FX.txt 中“国家反诈中心”域名与“反诈中心”标注的 IP 段' "$FX"
grep -Fq '96110 是电话专线，不是 DNS 名称' "$FX" || grep -Fq '96110 本身是电话专线，并非 DNS 名称' "$FX"
# General subscription list and dedicated FX list stay in their separate settings lists.
grep -Fq '[list:rule]' "$ROOT/scripts/default.conf"
grep -Fq '[list:fx]' "$ROOT/scripts/default.conf"
echo 'FX vs generic rules UI scope regression: PASS'
