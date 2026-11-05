#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
grep -Fq 'builtin://NoAppDownload.txt|【网页去开屏/跳转提示】NoAppDownload 全量手机网页打开 App、扫码下载与客户端提示' "$CONF"
grep -Fq 'builtin://Adblock_Watermark.txt|【网页去水印】内置 DOM/CSS 水印元素规则' "$CONF"
grep -Fq 'builtin://RunningCheese_Watermark.txt|【网页水印补充】' "$CONF"
grep -Fq 'builtin://RunningCheese_Popup.txt|【网页浮层弹窗补充】' "$CONF"
grep -Fq 'builtin://AdultSite_Elements_EasyList.txt|【成人网站广告元素】' "$CONF"
grep -Fq '! Title: NoAppDownload' "$ROOT/rulefiles/NoAppDownload.txt"
[ "$(grep -Ec '^[[:alnum:].,*-]+##' "$ROOT/rulefiles/AdultSite_Elements_EasyList.txt")" -ge 500 ]
[ "$(awk 'substr($0,1,2)=="||" {n++} END {print n+0}' "$ROOT/rulefiles/AdultSite_AdServers.txt")" -ge 200 ]
grep -Fq 'e.applyCosmeticFilters(req, resp)' "$ROOT/mitm/main.go"
grep -Fq 'func (e *engine) applyCosmeticFilters' "$ROOT/mitm/cosmetic.go"
grep -Fq 'cosmeticBodyLimit' "$ROOT/mitm/cosmetic.go"
grep -Fq 'cosmeticRuleLimit' "$ROOT/mitm/cosmetic.go"
grep -Fq 'safeCosmeticSelector' "$ROOT/mitm/cosmetic.go"
grep -Fq 'DNS/Hosts' "$ROOT/README.md"
grep -Fq '##.open-app' "$ROOT/rulefiles/NoAppDownload.txt" || grep -Fq '##.open-app-bar' "$ROOT/rulefiles/NoAppDownload.txt"
grep -Fq '##.watermark' "$ROOT/rulefiles/Adblock_Watermark.txt"
if grep -Fq 'DNS/Hosts 规则可以去除水印' "$ROOT/README.md"; then echo 'FAIL: unsafe watermark claim' >&2; exit 1; fi
printf '%s\n' 'General rule-list splash/watermark cosmetic engine regression: PASS'
grep -Fq 'builtin_cosmetic_rules_v1' "$ROOT/scripts/util.sh"
grep -Fq 'FX_MODDIR' "$ROOT/scripts/mitm-engine.sh"
