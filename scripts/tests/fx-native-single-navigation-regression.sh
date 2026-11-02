#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
test -s "$JAVA"
grep -Fq 'case 1: return "pageHosts";' "$JAVA"
grep -Fq 'new String[]{"pageVpn", "pageHosts", "pagePrivacy",' "$JAVA"
grep -Fq "#screen>.navbar,#screen .navbar,#bottomNav,#bottom-nav,.bottom-nav," "$JAVA"
grep -Fq "if(id==='pageHosts'&&!page){id='pageAd';page=document.getElementById(id);}" "$JAVA"
grep -Fq "var names=id==='pageHosts'?['ad','hosts']:(id==='pageAd'?['ad']" "$JAVA"
grep -Fq '该功能页面未能加载，请检查内置 WebUI 页面资源。' "$JAVA"
grep -Fq 'onReceivedError(WebView view, WebResourceRequest request,' "$JAVA"
grep -Fq 'onReceivedHttpError(WebView view, WebResourceRequest request,' "$JAVA"
grep -Fq 'webViewLoaded = false;' "$JAVA"
grep -Fq '点击底部任一标签可重试。' "$JAVA"
SHELL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
grep -Fq 'fontSize = 15.sp' "$SHELL"
grep -Fq 'fontWeight = FontWeight.Bold' "$SHELL"
grep -Fq 'rootStatus.setMaxWidth(dp(132));' "$JAVA"
grep -Fq 'toolbar.addView(rootStatus, new LinearLayout.LayoutParams(dp(132), -2));' "$JAVA"
grep -Fq "if(!page||!page.children.length)return false;" "$JAVA"
grep -Fq "var pages=document.querySelectorAll('#screen .page');" "$JAVA"
grep -Fq "page.classList.add('on');page.scrollTop=0;" "$JAVA"
grep -Fq "navItems[n].classList.toggle('on',navItems[n].getAttribute('data-tab')===navTab);" "$JAVA"
grep -Fq "getComputedStyle(page).display!=='none'" "$JAVA"
GLASS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
grep -Fq 'val selectedIndexProvider: () -> Int = remember { { selected } }' "$GLASS"
grep -Fq 'selectedTabIndex = selectedIndexProvider' "$GLASS"

grep -Fq 'ViewTreeLifecycleOwner.set(shell, this);' "$JAVA"
grep -Fq 'ViewTreeViewModelStoreOwner.set(shell, this);' "$JAVA"
grep -Fq 'ViewTreeSavedStateRegistryOwner.set(shell, this);' "$JAVA"
grep -Fq 'ViewTreeLifecycleOwner.set(designModePanel, this);' "$JAVA"
grep -Fq 'ViewTreeViewModelStoreOwner.set(designModePanel, this);' "$JAVA"
grep -Fq 'ViewTreeSavedStateRegistryOwner.set(designModePanel, this);' "$JAVA"

grep -Fq 'onTabSelected(index)' "$GLASS"
! grep -Fq 'if (selected != index)' "$GLASS" || { echo 'direct Liquid tab taps must not be gated by selected state' >&2; exit 1; }
echo 'FX native single-navigation, Compose lifecycle-owner and WebUI route regression: PASS'
