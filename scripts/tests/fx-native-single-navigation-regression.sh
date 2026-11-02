#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
test -s "$JAVA"
grep -Fq 'case 1: return "pageHosts";' "$JAVA"
grep -Fq 'new String[]{"pageVpn", "pageHosts", "pagePrivacy",' "$JAVA"
grep -Fq "#screen>.navbar,#screen .navbar,#bottomNav,#bottom-nav,.bottom-nav," "$JAVA"
grep -Fq "if(id==='pageHosts'&&!page){id='pageAd';page=document.getElementById(id);}" "$JAVA"
grep -Fq "id==='pageHosts'?['hosts','ad']:(id==='pageAd'?['ad']" "$JAVA"
grep -Fq '该功能页面未能加载，请检查内置 WebUI 页面资源。' "$JAVA"
echo 'FX native single-navigation and WebUI route regression: PASS'
