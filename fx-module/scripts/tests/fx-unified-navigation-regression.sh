#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
java="$root/adhook/app/src/main/java/de/privacyguard/adhook"
manifest="$root/adhook/app/src/main/AndroidManifest.xml"
shell="$java/FxNativeAppShell.kt"
router="$java/FxNativeTabRouter.java"
host="$java/FxNativeTabActivity.java"
vpn="$java/FxNativeVpnActivity.java"
ad="$java/imported/ad/FxYulongAdActivity.java"
ad_general="$java/imported/ad/FxYulongAdGeneralActivity.java"
gkd="$java/FxGkdAutomationActivity.java"
privacy="$java/FxNativePrivacySettingsActivity.java"
scripts="$java/FxQuickJsScriptActivity.java"
hook="$java/MainActivity.java"
settings="$java/FxNativeSettingsActivity.java"
hook_tools="$java/imported/dia/FxDiaGlobalSettingsActivity.java"
backup="$java/imported/dia/FxDiaBackupActivity.java"
dex="$java/imported/dia/FxDiaDexBrowserActivity.java"
dia_scripts="$java/imported/dia/FxDiaScriptLibraryActivity.java"
dia_browser="$java/imported/dia/FxDiaActivityBrowserActivity.java"
licenses="$java/FxOpenSourceLicensesActivity.java"

for file in "$manifest" "$shell" "$router" "$host" "$vpn" "$ad" "$ad_general" "$gkd" "$privacy" "$scripts" "$hook" "$settings" "$hook_tools" "$backup" "$dex" "$dia_scripts" "$dia_browser"; do
  test -s "$file" || { echo "FAIL: missing canonical native navigation source: $file" >&2; exit 1; }
done

# The public bottom navigation has exactly six canonical labels and routes
# to native feature hosts; it never selects a second app or an external APK.
grep -Fq 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")' "$shell"
grep -Fq 'destination = FxNativeVpnActivity.class;' "$router"
grep -Fq 'destination = de.privacyguard.adhook.imported.ad.FxYulongAdActivity.class;' "$router"
grep -Fq 'destination = FxNativePrivacySettingsActivity.class;' "$router"
grep -Fq 'destination = FxQuickJsScriptActivity.class;' "$router"
grep -Fq 'destination = MainActivity.class;' "$router"
grep -Fq 'destination = FxNativeSettingsActivity.class;' "$router"
grep -Fq 'FxNativeTabRouter.navigate(this, index)' "$host"
grep -Fq 'finish();' "$host"
grep -Fq 'LiquidBottomTabs(' "$shell"

# VPN tab uses the single FX route controller and subscription model. The
# Yulong legacy VPN service must not be launched from the integrated UI.
grep -Fq 'setContentViewWithNativeTabs(scroll, 0);' "$vpn"
grep -Fq 'setText("启动 VPN")' "$vpn"
grep -Fq 'setText("停止 VPN")' "$vpn"
grep -Fq 'showAddSubscriptionDialog()' "$vpn"
grep -Fq 'nativeVpnRootCommand(' "$vpn"
! grep -Fq 'startService(new Intent(this, AdBlockVpnService.class))' "$vpn"

# Ad is the only visible second-tab name; Yulong's imported filtering/DNS/
# Hosts suite stays inside the same Activity package and shared native shell.
grep -Fq 'Ad · 广告过滤控制中心' "$ad"
grep -Fq 'setContentViewWithNativeTabs(root, 1)' "$ad"
grep -Fq 'extends de.privacyguard.adhook.FxNativeTabActivity' "$ad"
grep -Fq 'Ad/Hosts' "$ad" && { echo "FAIL: visible Ad label must not be Ad/Hosts" >&2; exit 1; } || :
# All major native Ad/Hook dialogs must go through the skin-aware FX builder.
for page in "$ad" "$ad_general" "$gkd" "$hook"; do
  grep -Fq 'fxDialogBuilder()' "$page" || {
    echo "FAIL: native page has no shared skin-aware dialog entry: $page" >&2; exit 1;
  }
  ! grep -Fq 'new AlertDialog.Builder(this)' "$page" || {
    echo "FAIL: native page bypasses the shared dialog renderer: $page" >&2; exit 1;
  }
done

# Privacy is backed by the module-declared schema and the native root writer.
grep -Fq 'setContentViewWithNativeTabs(scroll, 2);' "$privacy"
grep -Fq 'native-privacy-settings.json' "$privacy"
grep -Fq 'native-privacy-settings.sh' "$privacy"

# The Scripts tab owns the QuickJS-NG list, HTTPS subscriptions, supported
# config import and the Dia script-library subdestination.
grep -Fq 'setContentViewWithNativeTabs(root, 3);' "$scripts"
grep -Fq 'QuickJS 脚本清单' "$scripts"
grep -Fq 'native-jsruntime-control.sh' "$scripts"
grep -Fq 'FxDiaScriptLibraryActivity.class' "$scripts"
grep -Fq 'Surge / Loon / Quantumult X' "$scripts" || grep -Fq 'Egern / Stash' "$scripts"

# Hook keeps target policy and LSPosed scope; Dia/GKD tools are nested pages
# in the same APK. DEX browsing is read-only unless explicitly invoked with
# a method-picker extra for an eligible debuggable user application.
grep -Fq 'setContentViewWithNativeTabs(root, 4);' "$hook"
grep -Fq 'private void publishConfig()' "$hook"
grep -Fq 'private void requestScope()' "$hook"
grep -Fq 'GKD 自动化' "$hook"
grep -Fq 'FxGkdAutomationActivity.class' "$hook"
grep -Fq 'FxDiaScriptLibraryActivity.class' "$hook"
grep -Fq 'FxDiaActivityBrowserActivity.class' "$hook"
grep -Fq 'Dia DEX 只读浏览' "$hook"
grep -Fq 'FxDiaDexBrowserActivity.class' "$hook"
grep -Fq 'Dia 工具箱' "$hook"
grep -Fq 'FxDiaToolsActivity.class' "$hook"
grep -Fq 'setContentViewWithNativeTabs(root, 4);' "$JAVA/imported/dia/FxDiaToolsActivity.java"
grep -Fq 'Frida 环境与注入' "$hook"
grep -Fq 'FxDiaFridaActivity.class' "$hook"
grep -Fq 'allow_hook_method_pick' "$dex"
grep -Fq 'ApplicationInfo.FLAG_DEBUGGABLE' "$dex"
# Two fixed-string checks: the parse entry and the dexPick template it consumes.
grep -Fq 'DeveloperHookRule.parse' "$dex"
grep -Fq 'dexPick' "$dex"

# Global Settings is the single owner of app-wide visual modes and wallpaper;
# the nested Hook tools page must not expose duplicate visual preferences.
grep -Fq 'setContentViewWithNativeTabs(scroll, 5);' "$settings"
grep -Fq 'FxDesignModePanelKt.installFxDesignModePanel' "$settings"
grep -Fq 'FxUiMode.write(FxNativeSettingsActivity.this, next)' "$settings"
grep -Fq 'FxWallpaperStore.saveFromUri(this, uri)' "$settings"
grep -Fq 'FxWallpaperStore.clear(this)' "$settings"
grep -Fq 'setContentViewWithNativeTabs(root, 5)' "$licenses"
grep -Fq 'extends FxNativeTabActivity' "$licenses"
grep -Fq 'fxDialogBuilder()' "$licenses"
grep -Fq 'FxDiaBackupActivity.class' "$settings"
grep -Fq '打开 Hook 工具与运行设置' "$settings"
grep -Fq '‹ 返回设置' "$hook_tools"
grep -Fq 'Hook · 工具与运行设置' "$hook_tools"
! grep -Fq 'FxUiMode' "$hook_tools"
! grep -Fq 'FxWallpaperStore' "$hook_tools"

# Imported Dia browser, backup, editor and Script-library pages remain on the
# shared tab host instead of starting legacy standalone applications.
for page in "$backup" "$dex" "$dia_scripts" "$dia_browser"; do
  grep -Fq 'extends de.privacyguard.adhook.FxNativeTabActivity' "$page"
  grep -Fq 'setContentViewWithNativeTabs(' "$page"
done

# All destinations and nested migrated pages are in the single APK manifest.
for component in MainActivity FxNativeVpnActivity FxYulongAdActivity FxNativePrivacySettingsActivity FxQuickJsScriptActivity FxNativeSettingsActivity FxOpenSourceLicensesActivity FxDiaGlobalSettingsActivity FxDiaDexBrowserActivity FxDiaScriptLibraryActivity FxDiaActivityBrowserActivity FxDiaBackupActivity; do
  grep -Fq "$component" "$manifest" || {
    echo "FAIL: APK manifest missing integrated Activity: $component" >&2
    exit 1
  }
done

echo "PASS: unified six-tab native navigation, single FX app, and nested Dia/GKD/Hook/QuickJS destinations."
