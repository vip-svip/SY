#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook/imported/shield"

# KernelSU packages the app from fx-module. Require source parity for the
# exact six-mode role contract, rather than testing only the root APK tree.
for relative in \
  app/src/main/java/de/privacyguard/adhook/FxNativeSkin.java \
  app/src/main/java/de/privacyguard/adhook/HarmonySkinTokens.java \
  app/src/main/java/de/privacyguard/adhook/CupertinoSkinTokens.java \
  app/src/main/java/de/privacyguard/adhook/HarmonySkinRenderer.java \
  app/src/main/java/de/privacyguard/adhook/CupertinoSkinRenderer.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistPickerActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/BlacklistActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongDailySummaryActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongIntegrityActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java \
  app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScreenFilterActivity.java; do
  cmp -s "$ROOT/adhook/$relative" "$ROOT/fx-module/adhook/$relative" || {
    echo "FAIL: six-mode Shield source/module drift: $relative" >&2
    exit 1
  }
done
cmp -s "$ROOT/scripts/tests/fx-yulong-shield-six-tab-regression.sh" \
  "$ROOT/fx-module/scripts/tests/fx-yulong-shield-six-tab-regression.sh" || {
    echo "FAIL: six-mode Shield regression root/module copies differ" >&2
    exit 1
  }

python3 - "$APP/AndroidManifest.xml" "$JAVA" "$APP/java/de/privacyguard/adhook/MainActivity.java" "$APP/java/de/privacyguard/adhook/FxNativeTabActivity.java" "$APP/java/de/privacyguard/adhook/FxNativeAppShell.kt" "$APP/java/de/privacyguard/adhook/FxComposeSkinTokens.kt" "$APP/java/de/privacyguard/adhook/HarmonySkinTokens.java" "$APP/java/de/privacyguard/adhook/CupertinoSkinTokens.java" "$APP/java/de/privacyguard/adhook/FxNativeSkin.java" "$JAVA/WhitelistActivity.java" "$JAVA/WhitelistPickerActivity.java" "$JAVA/BlacklistActivity.java" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, shield_dir, main_path, tab_host_path, shell_path, tokens_path, harmony_tokens_path, cupertino_tokens_path, skin_path, whitelist_path, whitelist_picker_path, blacklist_path = map(Path, sys.argv[1:])
main = main_path.read_text(encoding="utf-8")
tab_host = tab_host_path.read_text(encoding="utf-8")
shell = shell_path.read_text(encoding="utf-8")
tokens = tokens_path.read_text(encoding="utf-8")
harmony_tokens = harmony_tokens_path.read_text(encoding="utf-8")
cupertino_tokens = cupertino_tokens_path.read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
android = "{http://schemas.android.com/apk/res/android}"
# The six primary destinations are fixed and index-compatible across Web/native pages.
labels = 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")'
assert labels in shell, "Native app shell must expose exactly the six fixed FX tabs in order"
assert "tabsCount = labels.size" in shell, "Glass navigation must use the same six-tab model"
assert ".height(tokens.tabBarHeightDp.dp)" in shell, "Native six-tab bars must use the active Skin geometry token"
assert ".padding(bottom = tokens.tabBarHeightDp.dp)" in shell, "Native page viewport must reserve the active Skin tab-bar height"
assert "tabBarHeightDp = 60" in tokens, "ClassicWebCompat 60dp tab-bar token missing"
assert "tabBarHeightDp = 72" in tokens, "FXLiquidNative 72dp tab-bar token missing"
assert "tabBarHeightDp = 68" in tokens, "MiuixStyle 68dp tab-bar token missing"
assert "tabBarHeightDp = HarmonySkinTokens.HarmonySpacingTokens.NAV_HEIGHT_DP" in tokens
assert "NAV_HEIGHT_DP = 72" in harmony_tokens, "HarmonyStyle 72dp tab-bar token missing"
assert "tabBarHeightDp = CupertinoSkinTokens.CupertinoSpacingTokens.NAV_HEIGHT_DP" in tokens
assert "NAV_HEIGHT_DP = 76" in cupertino_tokens, "CupertinoStyle 76dp tab-bar token missing"
assert "index < 0 || index > 5" in tab_host, "Native tab host must reject indices outside 0..5"
assert "Math.max(0, Math.min(5, selectedIndex))" in tab_host, "Native tab host must clamp selected index to six destinations"
assert "handleNativeTabIntent" in main and "tab >= 0 && tab <= 5" in main, "Native pages must route back to the fixed six-tab MainActivity"
for token in ("if (index == 5)", "else if (index == 4)", "else if (index >= 0 && index <= 3)"):
    assert token in main, f"MainActivity top-level tab route missing: {token}"
declared = {
    item.attrib.get(android + "name", "")
    for item in manifest.findall("./application/activity")
}
pages = {
    "FxYulongVirusDatabaseActivity.java": ".imported.shield.FxYulongVirusDatabaseActivity",
    "FxYulongScanActivity.java": ".imported.shield.FxYulongScanActivity",
    "FxYulongIntegrityActivity.java": ".imported.shield.FxYulongIntegrityActivity",
    "FxYulongRescueActivity.java": ".imported.shield.FxYulongRescueActivity",
    "FxYulongBatchCleanupActivity.java": ".imported.shield.FxYulongBatchCleanupActivity",
    "FxYulongScreenFilterActivity.java": ".imported.shield.FxYulongScreenFilterActivity",
    "FxYulongDailySummaryActivity.java": ".imported.shield.FxYulongDailySummaryActivity",
    "FxYulongWarningActivity.java": ".imported.shield.FxYulongWarningActivity",
    "WhitelistActivity.java": ".imported.shield.WhitelistActivity",
    "WhitelistPickerActivity.java": ".imported.shield.WhitelistPickerActivity",
    "BlacklistActivity.java": ".imported.shield.BlacklistActivity",
}
for filename, component in pages.items():
    assert any(name == component or name.endswith(component) for name in declared), (
        f"Manifest Activity missing: {component}"
    )
    source = (shield_dir / filename).read_text(encoding="utf-8")
    assert "extends de.privacyguard.adhook.FxNativeTabActivity {" in source, (
        f"{filename}: page must use the shared six-tab Activity host"
    )
    assert "setContentViewWithNativeTabs(root, 2);" in source, (
        f"{filename}: page must install the shared native tab shell for the Privacy destination"
    )
    assert "setContentView(root);" not in source, (
        f"{filename}: page bypasses the shared native tab shell"
    )
    assert source.count("setContentViewWithNativeTabs(root, 2);") == 1, (
        f"{filename}: expected exactly one Privacy-tab root installation"
    )

scan = (shield_dir / "FxYulongScanActivity.java").read_text(encoding="utf-8")
rescue = (shield_dir / "FxYulongRescueActivity.java").read_text(encoding="utf-8")
hub = (shield_dir / "FxYulongShieldActivity.java").read_text(encoding="utf-8")
assert 'text("隐私 · 安全防护中心"' in hub, "Shield hub must use the FX Privacy product identity"
assert "setContentViewWithNativeTabs(root, 2);" in hub, "Shield hub must select the Privacy tab"
black = blacklist_path.read_text(encoding="utf-8")
whitelist = whitelist_path.read_text(encoding="utf-8")
whitelist_picker = whitelist_picker_path.read_text(encoding="utf-8")
assert "STATE_SCAN_STATE_ID" in scan and "FxYulongScanStateStore.save" in scan and "onSaveInstanceState" in scan
assert "Intent.ACTION_DELETE" in scan and 'setPositiveButton("打开系统确认"' in scan
assert "Intent.ACTION_DELETE" in rescue
assert "FxYulongRescueActivity.class" in hub
assert "FxYulongDailySummaryActivity.class" in hub

# Rescue Center can be launched from either the Shield Hub or the persistent notification.
service = (shield_dir / "FxYulongRescueOverlayService.java").read_text(encoding="utf-8")
assert "Intent open=new Intent(this,FxYulongRescueActivity.class);" in service
assert "open.putExtra(FxYulongRescueActivity.EXTRA_OPENED_FROM_NOTIFICATION, true);" in service
assert "Intent open=new Intent(this,FxYulongShieldActivity.class);" in service, "floating bubble must continue opening the Shield Hub"
assert "getIntent().getBooleanExtra(EXTRA_OPENED_FROM_NOTIFICATION, false)" in rescue
assert "Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP" in rescue
assert "// Hub-launched rescue screens simply finish to the existing caller." in rescue, "Hub-origin Rescue Center must return to its existing caller"
assert "finish();" in rescue, "Hub-origin Rescue Center must finish rather than create a duplicate Hub"
assert "FxYulongWarningActivity.class" in scan
assert "FxYulongVirusDatabaseActivity.class" in hub
for key in ("STATE_PICKER_OPEN", "STATE_PICKER_QUERY", "STATE_PICKER_PAGE", "PREF_PICKER_STAGED", "STATE_PICKER_SCROLL_Y"):
    assert key in black, f"Blacklist picker state missing: {key}"
assert "pickerDialogOpen = savedInstanceState.getBoolean(STATE_PICKER_OPEN, false)" in black
assert "if (pickerDialogOpen) showAppPicker(true)" in black, "picker must reopen after app inventory is restored"
assert "scroll.post(() -> scroll.scrollTo(0, restorePickerY))" in black
assert "if (!isChangingConfigurations())" in black, "configuration recreation must not discard picker draft"
assert "currentBlacklist.addAll(staged)" in black, "only explicit confirmation may commit staged packages"
assert "pickerStaged.clear();" in black, "dismissed/cancelled picker draft must be cleared"
assert "FxYulongScanActivity.class" in hub
daily = (shield_dir / "FxYulongDailySummaryActivity.java").read_text(encoding="utf-8")
privacy_pages = {
    "FxYulongShieldActivity.java": ("隐私 · 安全防护中心",),
    "FxYulongDailySummaryActivity.java": ("隐私 · 每日安全总结", "‹ 返回隐私"),
    "FxYulongRescueActivity.java": ("隐私 · 救援中心", "‹ 返回隐私"),
    "FxYulongScreenFilterActivity.java": ("隐私 · 屏幕滤镜", "‹ 返回隐私"),
    "FxYulongVirusDatabaseActivity.java": ("隐私 · 病毒库管理", "‹ 返回隐私"),
    "FxYulongScanActivity.java": ("隐私 · 已安装应用扫描", "‹ 返回隐私"),
    "FxYulongWarningActivity.java": ("隐私 · 风险应用详情", "‹ 返回隐私"),
    "FxYulongBatchCleanupActivity.java": ("隐私 · 批量清理 · 逐项确认", "‹ 返回隐私"),
    "FxYulongIntegrityActivity.java": ("隐私 · 应用签名与完整性", "‹ 返回隐私"),
}
for filename, tokens in privacy_pages.items():
    source = (shield_dir / filename).read_text(encoding="utf-8")
    for token in tokens:
        assert token in source, f"{filename} is not presented as an FX Privacy page: {token}"
for token in ("shield_prefs", "automatic_scan_last_result", "FxYulongProtectionService", "FxYulongRescueOverlayService"):
    assert token in daily, f"daily summary data source missing: {token}"
assert 'body.addView(button("返回隐私首页",this::finish));' in daily
assert 'body.addView(button("返回隐私首页",()->startActivity(new Intent(this,FxYulongShieldActivity.class))));' not in daily
assert r'+"\\n"' not in daily, "daily summary must render real line breaks, not literal \\n"
assert r'+"\n"' in daily, "daily summary service/permission lines must use newline separators"
warning = (shield_dir / "FxYulongWarningActivity.java").read_text(encoding="utf-8")
scan = (shield_dir / "FxYulongScanActivity.java").read_text(encoding="utf-8")
screen_filter = (shield_dir / "FxYulongScreenFilterActivity.java").read_text(encoding="utf-8")
virus_db = (shield_dir / "FxYulongVirusDatabaseActivity.java").read_text(encoding="utf-8")
integrity = (shield_dir / "FxYulongIntegrityActivity.java").read_text(encoding="utf-8")
skin = skin_path.read_text(encoding="utf-8")
renderer_dir = skin_path.parent
harmony_renderer = (renderer_dir / "HarmonySkinRenderer.java").read_text(encoding="utf-8")
cupertino_renderer = (renderer_dir / "CupertinoSkinRenderer.java").read_text(encoding="utf-8")
for token in ("Intent.ACTION_DELETE",
              "WHITELIST_KEY", "AlertDialog", "package:"):
    assert token in warning, f"warning confirmation/safety contract missing: {token}"

# All six renderers consume the same new page/toolbar role contract.
for role in ('fx-page-root', 'fx-toolbar', 'fx-toolbar-title', 'fx-toolbar-action'):
    assert role in skin, f"Default/Classic/Glass/Miuix shared renderer is missing {role}"
    assert role in harmony_renderer, f"Harmony renderer is missing {role}"
    assert role in cupertino_renderer, f"Cupertino renderer is missing {role}"

# Native Harmony/Cupertino renderers must treat transient/terminal page states
# as semantic components, not plain body text, with their own status palettes.
for role in ('fx-empty-state', 'fx-loading-state', 'fx-error-state', 'fx-success-state'):
    assert f'"{role}".equals(role)' in harmony_renderer, f"Harmony renderer is missing {role}"
    assert f'"{role}".equals(role)' in cupertino_renderer, f"Cupertino renderer is missing {role}"
for token in ('EMPTY_STATE_SURFACE', 'LOADING_STATE_SURFACE', 'ERROR_STATE_SURFACE', 'SUCCESS_STATE_SURFACE'):
    assert token in harmony_tokens, f"Harmony status token missing: {token}"
    assert token in cupertino_tokens, f"Cupertino status token missing: {token}"

# Global HUAWEI/Cupertino renderers consume explicit semantic roles from Shield.
batch = (shield_dir / "FxYulongBatchCleanupActivity.java").read_text(encoding="utf-8")
rescue_page = (shield_dir / "FxYulongRescueActivity.java").read_text(encoding="utf-8")
assert 'pageTitle.setTag("fx-title:18")' in hub
for token in ('panel.setTag("fx-card")', 'heading.setTag("fx-card-title")',
              'description.setTag("fx-card-detail")', 'button.setTag("fx-action-row")',
              'installScanSwitch.setTag("fx-switch-row")'):
    assert token in hub, f"Shield hub is missing shared Skin role {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'back.setTag("fx-toolbar-action")', 'pageTitle.setTag("fx-toolbar-title")',
              'body.setTag("fx-card-group")', 'safetyNote.setTag("fx-risk-suspect")',
              'state.setTag("fx-card-detail")', 'state.setTag("fx-error-state")',
              'state.setTag("fx-success-state")', 'current.setTag("fx-risk-certain")',
              'current.setTag("fx-empty-state")', 'current.setTag("fx-card-title")',
              'uninstall.setTag("fx-primary-action")'):
    assert token in batch, f"Shield batch-cleanup page is missing shared Skin role/state {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'header.addView(button("‹ 返回隐私", this::returnToShieldHub, "fx-toolbar-action"))',
              'pageTitle.setTag("fx-toolbar-title")', 'body.setTag("fx-card-group")',
              'p.setTag("fx-card")', 'heading.setTag("fx-card-title")',
              'description.setTag("fx-card-detail")', 'status.setTag("fx-card-detail")',
              'setStatus(String value, String role)',
              'setStatus("已刷新前台应用信息。", "fx-success-state")',
              'setStatus("当前没有可处理的前台应用包名。", "fx-error-state")',
              'setStatus("管控名单已清空。", "fx-success-state")'):
    assert token in rescue_page, f"Shield Rescue page is missing shared Skin role/state {token}"
assert 'status.setTag("fx-empty-state"); status.setTag("fx-card-detail");' not in rescue_page
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'backBtn.setTag("fx-toolbar-action")', 'title.setTag("fx-toolbar-title")',
              'blacklistDataWarningView.setTag("fx-error-state")',
              'trustAllBtn.setTag("fx-action-text")', 'hint.setTag("fx-card-detail")',
              'blacklistEmptyText.setTag("fx-empty-state")',
              'blacklistContainer.setTag("fx-card-group")', 'listTitle.setTag("fx-section:已加入管控")',
              'row.setTag("fx-list-row")', 'nameTv.setTag("fx-list-title")',
              'pkgTv.setTag("fx-list-subtitle")', 'removeBtn.setTag("fx-action-row")',
              'more.setTag("fx-action-text")'):
    assert token in black, f"Shield Blacklist page is missing shared Skin role {token}"
for token in ('count.setTag("fx-card-detail")', 'rows.setTag("fx-card-group")',
              'more.setTag("fx-action-row")', 'optionRow.setTag("fx-list-row")',
              'optionRow.addView(check', 'rows.addView(optionRow'):
    assert token in black, f"Blacklist picker is missing all-mode component role {token}"
assert 'final AlertDialog dialog = fxDialogBuilder()' in black, "Blacklist picker must retain the shared six-mode dialog host"
assert 'blacklistSearchInput.setTag("fx-search-input")' in black, "Blacklist page search field must use all-mode search styling"
assert 'search.setTag("fx-search-input")' in black, "Blacklist picker search field must use all-mode search styling"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'back.setTag("fx-toolbar-action")', 'title.setTag("fx-toolbar-title")',
              'sub.setTag("fx-card-detail")', 'add.setTag("fx-toolbar-action")',
              'summary.setTag("fx-card")', 'searchInput.setTag("fx-search-input")',
              'emptyHint.setTag("fx-card")', 'whitelistContainer.setTag("fx-card-group")',
              'row.setTag("fx-list-row")', 'name.setTag("fx-list-title")',
              'pkg.setTag("fx-list-subtitle")', 'remove.setTag("fx-action-text")',
              'countText.setTag(whitelistDataWarning.isEmpty() ? "fx-card-title" : "fx-error-state")'):
    assert token in whitelist, f"Whitelist page is missing shared six-mode role {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'cancel.setTag("fx-toolbar-action")', 'title.setTag("fx-toolbar-title")',
              'bar.setTag("fx-toolbar")', 'submitView.setTag("fx-primary-action")',
              'searchInput.setTag("fx-search-input")', 'countView.setTag("fx-card-detail")',
              'selectAllView.setTag("fx-action-text")', 'row.setTag("fx-list-row")',
              'h.name.setTag("fx-list-title")', 'h.pkg.setTag("fx-list-subtitle")',
              'countView.setTag(loadFinished ? "fx-error-state" : "fx-loading-state")'):
    assert token in whitelist_picker, f"Whitelist picker is missing six-mode role {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'pageTitle.setTag("fx-toolbar-title")', 'body.setTag("fx-card-group")',
              'c.setTag("fx-card")', 'heading.setTag("fx-card-title")',
              'description.setTag("fx-card-detail")',
              'button("打开完整应用扫描",()->startActivity(new Intent(this,FxYulongScanActivity.class)),"fx-primary-action")',
              'button("返回隐私首页",this::finish,"fx-action-text")'):
    assert token in daily, f"Shield Daily Summary is missing shared Skin role {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'pageTitle.setTag("fx-toolbar-title")', 'status.setTag("fx-card-detail")',
              'status.setTag("fx-loading-state")',
              'status.setTag(result.scanComplete ? "fx-success-state" : "fx-error-state")',
              'status.setTag("fx-error-state")',
              'resultHeading.setTag("fx-section:风险结果")',
              'contentScan.setTag("fx-switch-row")'):
    assert token in scan, f"Shield Scan page is missing shared Skin state/role {token}"
assert 'Button b=new Button(this);b.setTag("fx-action-row")' in scan, "Shield Scan action helper is missing shared Skin role"
assert 'scan=action("开始扫描",this::startScan);' in scan, "Shield Scan action must continue using the Skin-tagged action helper"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'pageTitle.setTag("fx-toolbar-title")', 'b.setTag("fx-action-row")',
              'panel.setTag("fx-card")', 'heading.setTag("fx-card-title")',
              'description.setTag("fx-card-detail")', 'enabled.setTag("fx-switch-row")',
              'volumeAdjust.setTag("fx-switch-row")', 'seek.setTag("fx-seekbar")',
              'preset.setTag("fx-select-input")',
              'FxNativeSkin.applySpinnerChoiceSkin(',
              'getView(int position, View convertView',
              'getDropDownView(int position, View convertView'):
    assert token in screen_filter, f"Shield Screen Filter is missing shared Skin role {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'pageTitle.setTag("fx-toolbar-title")', 'b.setTag("fx-action-row")',
              'panel.setTag("fx-card")', 'heading.setTag("fx-card-title")',
              'listRows.setTag("fx-card-group")', 'row.setTag("fx-list-row")',
              'label.setTag("fx-list-title")', 'status.setTag("fx-list-subtitle")',
              'target.setTag("fx-error-state")', 'contentSummary.setTag("fx-loading-state")',
              'summary.setTag("fx-loading-state")', 'summary.setTag(anyListFailed',
              'contentSummary.setTag(!contentError.isEmpty()'):
    assert token in virus_db, f"Shield Virus DB page is missing shared Skin role/state handling {token}"
for token in ('root.setTag("fx-page-root")', 'header.setTag("fx-toolbar")',
              'view.setTag(role)', 'pageTitle.setTag("fx-toolbar-title")',
              'signerCard.setTag("fx-card")', 'signerHeading.setTag("fx-card-title")',
              'moduleCard.setTag("fx-card")', 'moduleHeading.setTag("fx-card-title")',
              'moduleStatus.setTag("fx-empty-state")',
              'moduleStatus.setTag("fx-loading-state")',
              'moduleStatus.setTag(completedExitCode == 0 ? "fx-success-state" : "fx-error-state")',
              'moduleStatus.setTag("fx-error-state")',
              'checkButton = button("检查模块完整性", this::checkModule, "fx-primary-action")',
              'boundaryCard.setTag("fx-risk-suspect")',
              'boundaryHeading.setTag("fx-risk-title-suspect")',
              'boundaryNote.setTag("fx-card-body")',
              'int exitCode = Integer.MIN_VALUE;', 'final int completedExitCode = exitCode;' ):
    assert token in integrity, f"Shield Integrity page is missing shared Skin role/state handling {token}"
assert 'moduleStatus.setTag(result.exitCode == 0' not in integrity, "Integrity result must be captured outside the try scope"
for token in ('if (view instanceof android.widget.SeekBar)',
              'control.setProgressTintList', 'control.setProgressBackgroundTintList',
              'control.setThumbTintList'):
    assert token in skin, f"Shared Skin adapter is missing SeekBar renderer token {token}"
print("PASS: Shield database/scan/integrity/rescue/daily-summary/warning pages retain six-tab shell and existing navigation/result/removal contracts")
PY
