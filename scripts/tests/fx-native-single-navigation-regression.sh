#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
DASH="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeDashboard.kt"
SHELL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
SETTINGS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt"
test -s "$JAVA"
test -s "$DASH"
test -s "$SHELL"
test -s "$SETTINGS"

# Six native destinations remain the only primary navigation.
grep -Fq 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")' "$SHELL"
grep -Fq '.padding(bottom = 72.dp)' "$SHELL"
grep -Fq 'LiquidBottomTabs(' "$SHELL"
grep -Fq 'onTabSelected(index)' "$SHELL"

# Main dashboard now mounts a Compose-native page host; it must not construct or load a WebView.
grep -Fq 'private androidx.compose.ui.platform.ComposeView nativeDashboard;' "$JAVA"
grep -Fq 'FxNativeDashboardKt.installFxNativeDashboard(nativeDashboard, lastWebTabIndex' "$JAVA"
grep -Fq 'private void renderNativeDashboard(int index)' "$JAVA"
grep -Fq 'FxNativeDashboardKt.installFxNativeDashboard(nativeDashboard, index' "$JAVA"
grep -Fq 'root.addView(nativeDashboard, new LinearLayout.LayoutParams(-1, 0, 1));' "$JAVA"
dashboard_block=$(sed -n '/private void showWebDashboard() {/,/private void renderNativeDashboard(int index)/p' "$JAVA")
printf '%s' "$dashboard_block" | grep -Fq 'new androidx.compose.ui.platform.ComposeView(this)'
printf '%s' "$dashboard_block" | grep -Fq 'mountNativeShell(root)'
! printf '%s' "$dashboard_block" | grep -Fq 'new WebView(this)'
! printf '%s' "$dashboard_block" | grep -Fq 'webView.loadUrl'
! grep -Fq 'navigateWebPage("pageMore")' "$JAVA"

# The four management destinations contain native, scrollable content rather than WebView routes.
for symbol in VpnPage HostsPage PrivacyPage ScriptPage; do
  grep -Fq "private fun $symbol(" "$DASH"
done
for label in 'VPN 控制中心' '广告与 Hosts' '隐私保护' '脚本中心' '本地 Hosts' '订阅规则' '系统 Hosts' 'MITM 与证书设置'; do
  grep -Fq "$label" "$DASH"
done
grep -Fq '原生 UI 入口已建立' "$DASH"
grep -Fq '尚未连接真实 VPN 后端' "$DASH"
grep -Fq '尚未从模块脚本目录读取数据' "$DASH"

# Hook and Settings remain native screens and the six-tab routes stay stable.
grep -Fq 'private void showAppList()' "$JAVA"
grep -Fq 'private void showHookHub()' "$JAVA"
grep -Fq 'private void showSettings()' "$JAVA"
grep -Fq 'FxDesignModePanelKt.installFxDesignModePanel' "$JAVA"
grep -Fq 'private void addNativeSettingEntry(' "$JAVA"
grep -Fq 'selectedBottomTab = 4;' "$JAVA"
grep -Fq 'selectedBottomTab = 5;' "$JAVA"
grep -Fq 'ModeCard("miuix"' "$SETTINGS"
grep -Fq 'ModeCard("glass"' "$SETTINGS"
! grep -Fq 'ModeCard("web"' "$SETTINGS"

echo 'FX native six-page UI, single navigation and visible action regression: PASS'
