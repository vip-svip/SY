#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
LISTS="$ROOT/scripts/native-managed-lists.sh"
test -s "$LISTS"
MODULE_LISTS="$ROOT/fx-module/scripts/native-managed-lists.sh"
test -s "$MODULE_LISTS"
cmp -s "$LISTS" "$MODULE_LISTS" || { echo "FAIL: KernelSU payload native-managed-lists.sh differs from Android UI backend" >&2; exit 1; }
sh -n "$LISTS"
sh -n "$MODULE_LISTS"
test -s "$JAVA"
SHELL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
grep -Fq 'fontSize = 15.sp' "$SHELL"
grep -Fq 'fontWeight = FontWeight.Bold' "$SHELL"
grep -Fq 'rootStatus.setMaxWidth(dp(132));' "$JAVA"
grep -Fq 'toolbar.addView(rootStatus, new LinearLayout.LayoutParams(dp(132), -2));' "$JAVA"
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
# Hook and Settings are native screens, not WebView placeholder routes.
grep -Fq 'private void showAppList()' "$JAVA"
grep -Fq 'private void loadAppsAsync()' "$JAVA"
grep -Fq 'search.addTextChangedListener' "$JAVA"
grep -Fq 'private void showSettings()' "$JAVA"
grep -Fq 'FxDesignModePanelKt.installFxDesignModePanel' "$JAVA"
grep -Fq 'selectedBottomTab = 4' "$JAVA"
grep -Fq 'selectedBottomTab = 5' "$JAVA"

# All four operational tabs render native page content; WebView is hidden as a
# compatibility bridge and cannot be exposed as page pixels or accessibility nodes.
grep -Fq 'private void renderNativePage(int index)' "$JAVA"
grep -Fq 'nativePageContent.removeAllViews();' "$JAVA"
grep -Fq 'content.addView(nativeVpnControls, new LinearLayout.LayoutParams(-1, -2));' "$JAVA"
grep -Fq 'private void addNativeSettingEntry(String heading, String summary, String detail)' "$JAVA"
grep -Fq 'private void buildNativeHostsPage()' "$JAVA"
grep -Fq 'showNativeManagedListDialog("ruleList", "广告过滤订阅")' "$JAVA"
grep -Fq 'showNativeManagedListAddDialog("ruleList", "添加广告过滤订阅", true)' "$JAVA"
grep -Fq 'showNativeManagedListDialog("domainList", "域名白名单")' "$JAVA"
grep -Fq 'showNativeManagedListDialog("blockList", "自定义黑名单")' "$JAVA"
grep -Fq 'private void showNativeManagedListDialog(String listId, String title)' "$JAVA"
grep -Fq 'private void showNativeManagedListItemActions(String listId, String title, int index,' "$JAVA"
grep -Fq 'private void showNativeManagedListAddDialog(String listId, String title, boolean subscription)' "$JAVA"
# Hosts/Ad list management is native Android UI backed by the module's
# locked, transactional native-managed-lists.sh command. Do not regress to
# the retired WebView JavaScript mutation bridge.
python3 - "$JAVA" "$LISTS" <<'PY'
from pathlib import Path
import sys

java = Path(sys.argv[1]).read_text(encoding="utf-8")
script = Path(sys.argv[2]).read_text(encoding="utf-8")

def section(source, start, end):
    a = source.index(start)
    b = source.index(end, a + len(start))
    assert b > a, f"missing section boundary: {start}"
    return source[a:b]

ui = section(java, "private void showNativeManagedListDialog(",
             "private void showNativeListDialog(")
mutation = section(java, "private void mutateNativeManagedList(",
                   "private void showNativeListDialog(")
assert "native-managed-lists.sh" in mutation, "native list edits must call the module-side managed list script"
assert 'shellQuote(operation)' in mutation and 'shellQuote(listId)' in mutation,     "operation and list identifier must be shell-quoted"
for token in ('case "add":', 'case "edit":', 'case "toggle":', 'case "delete":'):
    assert token in mutation, f"native list operation is missing: {token}"
for token in ('shellQuote(newValue)', 'shellQuote(newNote)', 'runNativeModuleCommand(command, 180000L',
              '列表已保存并应用。', '列表更新失败', 'showNativeManagedListDialog(listId, title)'):
    assert token in mutation, f"native list mutation contract missing: {token}"
assert "evaluateJavascript" not in ui and "webView" not in ui,     "Hosts/Ad managed lists must not use the retired WebView mutation bridge"
assert '"FXLIST1".equals(lines[0])' in ui, "UI must validate the native list response envelope"
assert "line.split(" in ui and "parts.length != 4" in ui, "UI must parse row index/value/note/enabled as four fields"

for token in (
    'ruleList) echo rule', 'domainList) echo domain', 'blockList) echo block',
    'valid_field()', 'valid_note()', 'list_rows()', 'append_row()', 'update_row()',
    'mutate_transaction()', 'mkdir "$LOCK"', 'tries -lt 20',
    'cp -p "$CONF" "$backup"', 'cp -p "$backup" "$CONF.restore.$$"',
    'chmod 600 "$CONF.restore.$$"', 'apply_mode=full', 'apply_mode=fast',
    'sh "$MP/scripts/apply.sh" "$apply_mode"', 'echo FXLIST1',
):
    assert token in script, f"managed list backend safety/transaction contract missing: {token}"
assert 'http://*|https://*' in script, "subscription inputs must remain URL-limited"
assert 'set -eu' in script and 'umask' not in script, "managed list script must fail closed"
print("PASS: native Hosts/Ad lists use fixed allowlisted IDs, quoted inputs, locking, rollback and real apply")
PY
grep -Fq 'private void buildNativePrivacyPage()' "$JAVA"
grep -Fq 'private void addNativeActionCard(String heading, String description, String actionLabel, Runnable action)' "$JAVA"
grep -Fq 'addNativeActionCard("应用内广告标识"' "$JAVA"
grep -Fq 'addNativeActionCard("Wi-Fi 扫描保护"' "$JAVA"
grep -Fq '先开启「隐私保护总开关」' "$JAVA"
grep -Fq 'addNativeActionCard("剪贴板读取与隔离"' "$JAVA"
grep -Fq 'addNativeActionCard("传感器访问与采样"' "$JAVA"
grep -Fq 'addNativeActionCard("位置访问保护"' "$JAVA"
grep -Fq 'addNativeActionCard("麦克风保护"' "$JAVA"
grep -Fq 'addNativeActionCard("摄像头访问保护"' "$JAVA"
grep -Fq 'addNativeActionCard("媒体查询与 EXIF"' "$JAVA"
grep -Fq 'addNativeActionCard("只读会员状态诊断"' "$JAVA"
grep -Fq 'private void focusPendingPrivacySection()' "$JAVA"
grep -Fq 't.setTag("fx-section:" + s);' "$JAVA"
grep -Fq 'nativeScroll.smoothScrollTo(0, Math.max(0, child.getTop() - dp(12)))' "$JAVA"
grep -Fq 'addNativeActionCard("通知监听与权限提示"' "$JAVA"
grep -Fq 'private void buildNativeScriptPage()' "$JAVA"
grep -Fq 'private void showHostsEditor(String spec, int page)' "$JAVA"
grep -Fq 'private void writeHostsPage(String spec, int start, int originalLines, String text, AlertDialog dialog)' "$JAVA"
grep -Fq 'private void refreshNativeScriptList(LinearLayout rows, TextView status)' "$JAVA"
grep -Fq 'decoded.startsWith("FXSRC_B64:")' "$JAVA"
grep -Fq '本地 JS 源码 · 可手动运行 QuickJS-NG' "$JAVA"
grep -Fq 'private void runNativeLocalScript(int index' "$JAVA"
grep -Fq '启用条目后，可在脚本列表中点击「运行」手动调用 FX QuickJS-NG' "$JAVA" || { echo 'local JS add dialog still describes the runner as unimplemented' >&2; exit 1; }
grep -Fq 'local-run.sh' "$JAVA"
grep -Fq 'private static String nativeScriptSha256(String value)' "$JAVA"
grep -Fq 'expectedSha256' "$JAVA"
grep -Fq 'private void exportNativeScripts()' "$JAVA"
grep -Fq 'private void importNativeScriptDocument(String payload)' "$JAVA"
grep -Fq 'Object rawValue = entry.opt("value")' "$JAVA"
grep -Fq 'rawValue instanceof String' "$JAVA"
grep -Fq 'rawEnabled instanceof Boolean' "$JAVA"
grep -Fq 'new JSONObject(content).optString("format")' "$JAVA"
grep -Fq 'private void importNativeScriptEntry(JSONArray entries' "$JAVA"
grep -Fq '脚本配置导入结束：成功 ' "$JAVA"
grep -Fq 'private static boolean isSupportedNativeScriptValue(String raw)' "$JAVA"
grep -Fq 'private static int nativeScriptUtf8Bytes(String value)' "$JAVA"
grep -Fq 'nativeScriptUtf8Bytes(value) > 64 * 1024' "$JAVA"
grep -Fq 'private void importNativeScriptDocument(String payload)' "$JAVA"
grep -Fq 'FX-SCRIPT-LIST' "$JAVA"
grep -Fq 'importNativeScriptEntry(entries, 0, 0, 0)' "$JAVA"
grep -Fq '脚本文件超过 1 MiB' "$JAVA"
grep -Fq '脚本状态保存失败' "$JAVA"
grep -Fq 'private void showNativeScriptAddDialog()' "$JAVA"
grep -Fq 'private void pickNativeScriptFile()' "$JAVA"
grep -Fq 'REQUEST_NATIVE_SCRIPT_FILE = 4102' "$JAVA"
grep -Fq 'Intent.ACTION_OPEN_DOCUMENT' "$JAVA"
grep -Fq 'private void addNativeScriptValue(String raw, String sourceName)' "$JAVA"
grep -Fq 'String updatedValue = value.getText().toString();' "$JAVA"
grep -Fq 'String value = raw == null ? "" : raw;' "$JAVA"

grep -Fq 'name.toLowerCase(Locale.ROOT).endsWith(".json")' "$JAVA"
grep -Fq 'importNativeScriptDocument(content)' "$JAVA"
grep -Fq 'addNativeScriptValue(content, name == null ? "文件导入" : name)' "$JAVA"
grep -Fq '从文件导入脚本' "$JAVA"
grep -Fq 'private String nativeScriptStoreCommand(String action, String... args)' "$JAVA"
grep -Fq 'nativeScriptStoreCommand("list")' "$JAVA"
grep -Fq 'nativeScriptStoreCommand("add"' "$JAVA"
grep -Fq 'nativeScriptStoreCommand("update"' "$JAVA"
grep -Fq 'nativeScriptStoreCommand("toggle"' "$JAVA"
grep -Fq 'nativeScriptStoreCommand("delete"' "$JAVA"
grep -Fq 'private void syncNativeScriptRuntime()' "$JAVA"
grep -Fq 'scripts/jsruntime/sync-subs.sh' "$JAVA"
grep -Fq 'FXSCRIPT1' "$JAVA"
grep -Fq 'Base64.encodeToString' "$JAVA"
grep -Fq '从模块 settings.conf 读取脚本列表' "$JAVA"

grep -Fq 'private void exportNativeScripts()' "$JAVA"
grep -Fq 'REQUEST_NATIVE_SCRIPT_EXPORT = 4103' "$JAVA"
grep -Fq '导出脚本配置' "$JAVA"
grep -Fq '仅接受 HTTPS 订阅 URL 或本地 JS 源码' "$JAVA"
grep -Fq '脚本未保存：' "$JAVA"
grep -Fq 'private void showNativeScriptLogs()' "$JAVA"
grep -Fq 'private LinearLayout nativeScriptRows;' "$JAVA"
grep -Fq 'lastWebTabIndex == 3 && nativeScriptRows != null' "$JAVA"
grep -Fq 'refreshNativeScriptList(nativeScriptRows, nativeScriptStatus);' "$JAVA"
grep -Fq 'private void applyNativeHosts()' "$JAVA"
grep -Fq 'webView.setVisibility(View.INVISIBLE);' "$JAVA"
grep -Fq 'View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS' "$JAVA"
grep -Fq 'else renderNativePage(index);' "$JAVA"
! grep -Fq 'fullSettings.setOnClickListener' "$JAVA" || { echo 'Settings must not fall back to the WebUI' >&2; exit 1; }
grep -Fq '六个主页面均由 Android 原生视图承载' "$JAVA"
grep -Fq '查看 MITM / 证书状态' "$JAVA"
grep -Fq '查看最近 FX 模块日志' "$JAVA"
grep -Fq '管理系统 CA 信任（MITM / HTTPS）' "$JAVA"
grep -Fq 'private void showNativeCertificateManager()' "$JAVA"
grep -Fq 'private void showNativeCertificateList(JSONObject state)' "$JAVA"
grep -Fq 'private void runNativeCertificateAction(String action, String id)' "$JAVA"
grep -Fq 'certmgr.sh' "$JAVA"
grep -Fq 'pg_mitm_ca' "$JAVA"
grep -Fq 'pg_https_ca' "$JAVA"
grep -Fq 'private void showNativeRuntimeLogs()' "$JAVA"
grep -Fq 'private void attachHiddenWebViewBridge()' "$JAVA"
grep -Fq 'if (webView == null) showWebDashboard();' "$JAVA"
grep -Fq 'private void showNativeSettingsGroup(String panelId, String title)' "$JAVA"
grep -Fq 'native-privacy-settings.json' "$JAVA"
grep -Fq 'settings.conf' "$JAVA"
grep -Fq 'native-privacy-settings.sh' "$JAVA"
grep -Fq 'private void setNativePrivacySetting(String key' "$JAVA"
# The privacy settings screen also uses its native Root/module writer, not the
# retired WebView pgPersistNow() bridge.
python3 - "$JAVA" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
def method(start, end):
    a = source.index(start)
    b = source.index(end, a + len(start))
    return source[a:b]
reader = method("private void renderNativePrivacySettingsGroup(",
                "private void setNativePrivacySetting(")
writer = method("private void setNativePrivacySetting(",
                "private void finishNativePrivacySetting(")
assert "native-privacy-settings.sh" in reader and '" list"' in reader
assert 'runNativeModuleCommand(command, 120000L' in writer
assert "native-privacy-settings.sh" in writer and '" set "' in writer
assert 'finishNativePrivacySetting(control, enabled, true' in writer
assert 'finishNativePrivacySetting(control, previous, false' in writer
assert '配置已保存，但模块应用失败' in writer
assert 'pgPersistNow' not in reader and 'webView' not in reader and 'evaluateJavascript' not in writer
print("PASS: native privacy settings use the module writer and preserve failed-setting state")
PY
grep -Fq 'addNativeSettingsCategory("DNS、分流与连接策略", "vpnPanel")' "$JAVA"
grep -Fq 'addNativeSettingsCategory("Root / 模块隐藏", "rootPanel")' "$JAVA"
grep -Fq 'addNativeSettingsCategory("高级网络防护", "advPanel")' "$JAVA"
grep -Fq 'addNativeSettingsCategory("设备标识", "devicePanel")' "$JAVA"

# VPN tab exposes native Android controls routed through an explicit backend API, not hidden WebView button clicks.
grep -Fq 'buildNativeVpnControls();' "$JAVA"
grep -Fq 'private void buildNativeVpnControls()' "$JAVA"
grep -Fq 'nativeVpnSwitch.setOnCheckedChangeListener' "$JAVA"
grep -Fq 'private void showNativeVpnNodePicker()' "$JAVA"
grep -Fq 'nativeVpnNodeButton.setMaxLines(1);' "$JAVA"
grep -Fq 'nativeVpnNodeButton.setEllipsize(android.text.TextUtils.TruncateAt.END);' "$JAVA"
grep -Fq 'nativeVpnNodeButton.setText(node.isEmpty() ? "选择节点 · 尚未选择" : "更换节点 · 已选择");' "$JAVA"
grep -Fq '已选择 VPN 节点，点击更换' "$JAVA"
grep -Fq 'String endpoint = node.optString("host", "") + ":" + node.optString("port", "");' "$JAVA"
grep -Fq 'invokeNativeVpnApi("setEnabled"' "$JAVA"
grep -Fq 'invokeNativeVpnApi("setMode"' "$JAVA"
grep -Fq 'invokeNativeVpnApi("selectNode"' "$JAVA"
grep -Fq 'private boolean nativeVpnOperationBusy;' "$JAVA"
grep -Fq 'if (nativeVpnOperationBusy) return;' "$JAVA"
grep -Fq 'nativeVpnOperationBusy || !nativeVpnStatusQueued.compareAndSet(false, true)' "$JAVA"
grep -Fq 'private void testNativeVpnSelectedNodeLatency(Button button)' "$JAVA"
grep -Fq 'sh \"$MP/scripts/vpntest.sh\"' "$JAVA"
grep -Fq 'private void buildNativeVpnSubscriptionPanel()' "$JAVA"
grep -Fq 'private void showNativeVpnSubscriptionDialog()' "$JAVA"
grep -Fq 'private void startNativeVpnSubscriptionImport(String raw)' "$JAVA"
grep -Fq 'private void refreshNativeVpnSubscriptions()' "$JAVA"
grep -Fq 'private void setNativeVpnSubscriptionEnabled(int index, boolean enabled)' "$JAVA"
grep -Fq 'private void deleteNativeVpnSubscription(int index)' "$JAVA"
grep -Fq 'private void updateNativeVpnSubscription(int index, String url)' "$JAVA"
grep -Fq 'private void refreshAllNativeVpnSubscriptions()' "$JAVA"
grep -Fq 'window.fetchSub(u)' "$JAVA"
grep -Fq "window.importFromText(direct?'':u,body)" "$JAVA"
grep -Fq 'setThumbTintList' "$JAVA"
grep -Fq 'setTrackTintList' "$JAVA"
! grep -Fq 'vpnEnableToggle' "$JAVA"
! grep -Fq "document.querySelectorAll('#vpnModeSeg > *')" "$JAVA"
grep -Fq 'button.setEnabled(false);' "$JAVA"
grep -Fq 'nativeVpnSwitch.setEnabled(true)' "$JAVA"
grep -Fq '正在通过 Root 后端应用 VPN 设置' "$JAVA"
grep -Fq 'nativeVpnSwitch.setChecked(!"direct".equals(mode) && liveOn);' "$JAVA"
grep -Fq 'state.optBoolean("vpn_on", false)' "$JAVA"
grep -Fq 'state.optString("vpn_mode", "direct")' "$JAVA"
grep -Fq 'RootAccess.execute(nativeVpnRootCommand("status", "")' "$JAVA"
grep -Fq 'sh \"$MP/scripts/apply.sh\"' "$JAVA"
grep -Fq 'private void startNativeVpnPolling()' "$JAVA"
grep -Fq 'protected void onResume()' "$JAVA"
grep -Fq 'protected void onPause()' "$JAVA"
[ "$(grep -Fc '@Override protected void onPause()' "$JAVA")" -eq 1 ] || { echo 'MainActivity must define onPause exactly once' >&2; exit 1; }
[ "$(grep -Fc '@Override protected void onResume()' "$JAVA")" -eq 1 ] || { echo 'MainActivity must define onResume exactly once' >&2; exit 1; }
grep -Fq 'new org.json.JSONTokener(value).nextValue()' "$JAVA" || { echo 'VPN state must use the Android-supported JSONTokener instance API' >&2; exit 1; }
grep -Fq 'nativeVpnHandler.postDelayed(this, 5000L)' "$JAVA"
grep -Fq 'stopNativeVpnPolling();' "$JAVA"
grep -Fq 'nativeVpnHandler.removeCallbacks(nativeVpnPoll)' "$JAVA"
grep -Fq '#vpnStatusCard .vpn-toggle-wrap,#vpnModeSeg{display:none!important}' "$JAVA"
! grep -Fq 'if (selected != index)' "$GLASS" || { echo 'direct Liquid tab taps must not be gated by selected state' >&2; exit 1; }
echo 'FX native six-tab page structure, Compose lifecycle-owner and navigation regression: PASS'
