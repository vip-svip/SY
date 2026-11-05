#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
COS="$ROOT/mitm/cosmetic.go"
ADULT="$ROOT/rulefiles/AdultSite_AdPopup.txt"
ADHOST="$ROOT/rulefiles/AdultSite_AdHosts.txt"
WATER="$ROOT/rulefiles/Adblock_Watermark.txt"
NOAPP="$ROOT/rulefiles/NoAppDownload.txt"
ANTI="$ROOT/rulefiles/Adblock_Warning_Removal.txt"
fail() { echo "FAIL: $*" >&2; exit 1; }
for f in "$ADULT" "$ADHOST" "$WATER" "$NOAPP" "$ANTI"; do [ -s "$f" ] || fail "missing rule file: $f"; done
grep -Fq 'builtin://AdultSite_AdPopup.txt|【成人网站去广告弹窗】内置成人站广告层/弹窗选择器（保护正文、评论与播放器）|1' "$CONF" || fail "adult cosmetic rule not enabled"
grep -Fq 'builtin://Adblock_Warning_Removal.txt|【去反广告拦截提示】内置网页反广告拦截提醒元素规则|1' "$CONF" || fail "anti-adblock warning rules missing"
grep -Fq 'builtin://AdultSite_AdHosts.txt|【成人广告网络域名】内置成人广告供应商/弹窗域名（不屏蔽成人内容站根域）|1' "$CONF" || fail "adult ad host list must be active for requested ad coverage"
grep -Fq 'builtin://AdultSite_AdPopup.txt", "AdultSite_AdPopup.txt"' "$COS" || fail "MITM cosmetic engine does not load adult-site selectors"
# Every adult-site cosmetic rule must be domain-qualified and stay inside safe CSS selector syntax (attributes/combinators are supported).
awk '
  /^[[:space:]]*$/ || /^[[:space:]]*!/ {next}
  { n=split($0,a,"##"); selector=a[2]; if(n!=2 || a[1] !~ /^[A-Za-z0-9.-]+$/ || selector=="" || selector ~ /[{};<`]/ || selector ~ /url[[:space:]]*\(/ || selector ~ /expression[[:space:]]*\(/ || selector ~ /javascript:/) {print "unsafe selector: "$0 > "/dev/stderr"; bad=1} }
  END {if(bad) exit 1}
' "$ADULT" || fail "unsafe/unsupported adult-site selector"
# No full adult content-site host may be blocked by the optional DNS/hosts list; only ad-tech domains are allowed.
if grep -Eiq '^0\.0\.0\.0[[:space:]]+(pornhub\.com|xvideos\.com|xnxx\.com|xhamster\.com|redtube\.com|youporn\.com|spankbang\.com|tube8\.com|beeg\.com|eporner\.com|tnaflix\.com|porntrex\.com)$' "$ADHOST"; then fail "content site root blocked by ad-host list"; fi
for d in exoclick.com trafficjunky.net juicyads.com popads.net propellerads.com trafficstars.com realsrv.com; do grep -Eq "^0\\.0\\.0\\.0[[:space:]]+$d$" "$ADHOST" || fail "missing ad network $d"; done
# Keep the special FX list strictly separate from cosmetic and ad lists.
awk '
  /^\[list:fx\][[:space:]]*$/ {s=1;next}
  /^\[/ {s=0}
  s && /AdultSite|Adblock_Watermark|NoAppDownload|Adblock_Warning_Removal/ {bad=1}
  END {exit bad}
' "$CONF" || fail "non anti-fraud list leaked into FX rules"
# User requested an empty blacklist.
awk '/^\[list:block\][[:space:]]*$/{s=1;next} /^\[/{s=0} s && $0 !~ /^[[:space:]]*#/ && NF {bad=1} END{exit bad}' "$CONF" || fail "blacklist must remain empty"
echo 'PASS: adult popup rules are scoped to safe selectors; content hosts are never blocked; FX rules stay separate'
