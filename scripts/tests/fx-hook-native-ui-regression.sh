#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APK="${1:-$ROOT/adhook/app/build/outputs/apk/debug/app-debug.apk}"
SDK_ROOT="${ANDROID_HOME:-/usr/local/lib/android/sdk}"
AAPT="$SDK_ROOT/build-tools/34.0.0/aapt"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" ] || fail "native MainActivity source missing"
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" ] || fail "KernelSU root access helper missing"
grep -q "showDashboard()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "unified native dashboard missing"
grep -q 'outState.putInt("fx_last_web_tab", lastWebTabIndex);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "selected dashboard tab is not saved across Activity recreation"
grep -q 'outState.putInt("fx_selected_bottom_tab", selectedBottomTab);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "selected native bottom tab is not saved across Activity recreation"
grep -q 'outState.putString("fx_hook_screen"' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook screen kind is not saved across Activity recreation"
grep -q 'pendingRestorePackage = state.getString("fx_selected_package")' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "selected Hook target package is not saved for restoration"
grep -q 'if (restoreHookScreen)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook screen is not restored after Activity recreation"
grep -q 'pendingRestorePackage = null;' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "stale restored Hook target is not cleared when leaving its screen"
grep -q 'pendingWebPage = webPageForBottomTab(lastWebTabIndex);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "restored dashboard tab is not replayed after WebView reload"
grep -q 'webView.destroy();' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Activity destruction does not release the WebView"
grep -q 'deliverFileChooserResult(pendingFileChooser, null);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "pending document picker callback is not cancelled during Activity teardown"
grep -q 'deliverFileChooserResult(pending, null);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "file picker launch failure leaves WebView callback unresolved"
grep -Fq 'ValueCallback<Uri[]> pending = fileChooserCallback;' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "file picker result does not detach callback before delivery"
grep -q 'catch (RuntimeException malformedResult)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "malformed file picker result can strand WebView callback"
grep -Fq 'ValueCallback<Uri[]> previous = fileChooserCallback;' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "replaced file chooser callback is not detached before cancellation"
grep -Fq 'private static void deliverFileChooserResult(ValueCallback<Uri[]> callback, Uri[] result)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "file chooser callback delivery is not isolated"
grep -Fq 'deliverFileChooserResult(pending, results);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "file chooser result is not delivered through guarded callback"
grep -Fq 'catch (RuntimeException ignored)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "stale file chooser callback can crash Activity cleanup"
grep -q 'case "pageAd": tab = "ad"; break;' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Ad tab does not route to merged Hosts page"
grep -Fq 'FxNativeAppShellKt.installFxNativeAppShell' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "six-item Compose bottom navigation is not mounted"
grep -Fq 'listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "six-item native bottom navigation contract missing"
grep -Fq 'LiquidBottomTabs(' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "upstream Kyant LiquidBottomTabs is not used by FX glass navigation"
grep -Fq '.padding(bottom = 72.dp)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "page content is not inset above the persistent native bottom navigation"
grep -Fq 'tabsCount = labels.size' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "LiquidBottomTabs is not configured for all six FX destinations"
grep -Fq 'clickable(role = Role.Tab)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "native tabs are missing accessibility tab roles"
grep -Fq 'import androidx.compose.ui.semantics.selected' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "Compose selected semantics property import missing"
grep -Fq 'this.selected = selected == index' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "liquid tab selected state is not exposed to accessibility services"
grep -Fq 'lens(24f.dp.toPx(), 24f.dp.toPx())' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/glass/components/LiquidBottomTabs.kt" || fail "authentic liquid tab lens/refraction effect missing"
grep -Fq 'DampedDragAnimation' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/glass/components/LiquidBottomTabs.kt" || fail "liquid tab drag spring animation missing"
grep -Fq 'io.github.kyant0:capsule:2.1.1' "$ROOT/adhook/app/build.gradle" || fail "Kyant ContinuousCapsule dependency missing"
grep -Fq 'Capsule-LICENSE.txt' "$ROOT/adhook/app/src/main/assets/licenses/THIRD_PARTY_NOTICES.txt" || fail "Kyant Capsule license notice missing"
grep -Fq 'modified to support FX' "$ROOT/adhook/app/src/main/assets/licenses/THIRD_PARTY_NOTICES.txt" || fail "vendored LiquidBottomTabs source modifications are not disclosed"
grep -q "MAX_APP_ROWS_PER_PAGE = 40" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app list is not paginated"
grep -q 'new Thread(() -> {' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "installed app indexing is not moved off the UI thread"
grep -q '"fx-app-index"' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "background app-index worker missing"
grep -q "generation != appLoadGeneration" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "stale app-index result can overwrite a newer screen"
grep -q "appLoader.interrupt()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "app-index worker is not cancelled on Activity destruction"
grep -q "appendAppRows(0, Math.min(MAX_APP_ROWS_PER_PAGE, filtered.size()))" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app list eagerly renders all installed apps"
grep -Fq 'while (content.getChildCount() > 5) content.removeViewAt(5);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app list rerender removes its fixed explanatory hint"
[ "$(grep -Fc 'while (content.getChildCount() > 5) content.removeViewAt(5);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java")" -eq 2 ] || fail "async app-loader cleanup and list rerender must both preserve fixed header/search/hint views"
grep -q "appLabels.get(ai.packageName)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app labels are not cached for search"
grep -q "appIcons.get(ai.packageName)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app icons are not cached between search renders"
grep -Fq 'private void loadMissingAppIconsAsync()' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app icons are not loaded asynchronously"
grep -Fq 'getApplicationIcon(ai)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "background icon loader does not use PackageManager"
if sed -n '/private void appendAppRows/,/private void loadMissingAppIconsAsync/p' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" | grep -q 'getApplicationIcon'; then fail "Hook app row rendering decodes icons on the UI thread"; fi
grep -Fq 'appIconLoadGeneration' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "stale app icon results are not generation-guarded"
grep -q "return size() > 80;" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app icon cache is not memory-bounded"
grep -q "Locale.ROOT" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "case-insensitive app search is locale-dependent"
grep -q "sym_def_app_icon" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "removed-package icon fallback missing"
grep -q "getApplicationInfo(ai.packageName, 0)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "stale app rows are not revalidated before opening Hook settings"
grep -q "NameNotFoundException removed" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "uninstalled target app is not handled gracefully"
grep -q "申请 / 重新检查 Root 权限" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "root authorization action missing"
grep -q "new ProcessBuilder(\"su\", \"-c\", command)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "KernelSU su bridge missing"
grep -Eq "waitFor\(Math\.max\(1000L, timeoutMs\), TimeUnit\.MILLISECONDS\)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "bounded root command timeout missing"
grep -q "destroyForcibly()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "root timeout process cleanup missing"
grep -Fq 'RootAccess.execute(command, 60000L, 1024 * 1024)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "large Hook config publication has an unsafe short timeout"
grep -q 'fx-hook-targets.conf' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Remote Files target config path missing"
HOOK_ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
grep -Fq 'action.setText("OBSERVE")' "$HOOK_ACTIVITY" || fail "new custom Hook rules must default to observe-only"
grep -Fq 'NO_OP_VOID' "$HOOK_ACTIVITY" || fail "custom Hook UI does not expose the void-only method disable action"
grep -Fq 'DeveloperHookRule.parse(' "$HOOK_ACTIVITY" || fail "native custom Hook UI does not validate rules with the shared parser"
grep -Fq 'ruleId + "|" + method + "|" + actionText + "|" + priorityText' "$HOOK_ACTIVITY" || fail "native custom Hook UI drops the selected action or priority"
grep -Fq 'if (!debuggable && !"OBSERVE".equals(actionText))' "$HOOK_ACTIVITY" || fail "behavior replacement is not restricted to debuggable targets"
grep -Fq 'dev_hook_enabled 开启后：OBSERVE 记录元数据，RETURN_* 只作本地 Debug 测试 fixture' "$HOOK_ACTIVITY" || fail "Hook target status does not distinguish per-app opt-in from Debug fixtures"
! grep -Fq '自定义只读 Hook 可执行' "$HOOK_ACTIVITY" || fail "Hook target status still overstates all actions as read-only"
grep -Fq 'target != null && target.developerHooksEnabled && debuggableTarget' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "runtime custom rules are not gated by explicit per-app opt-in and FLAG_DEBUGGABLE"
grep -Fq 'MemberTestGate.isEnabled' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "Debug fixture runtime lacks the exact package/debug gate"
grep -Fq 'installDeveloperObservationHook(param.getClassLoader(), pkg' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "OBSERVE action is not wired to the metadata-only observer"
grep -Fq 'installDeveloperTypedReturnHook(param.getClassLoader(), pkg' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "typed Debug fixture actions are not wired into runtime"
grep -Fq 'installDeveloperVoidNoOpHook(param.getClassLoader(), pkg' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "void-only method disable action is not wired into runtime"
grep -Fq 'method.getReturnType() != void.class' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "method disable does not recheck the reflective void return type"
grep -Fq 'developerRuleForPackage' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java" || fail "custom rule package eligibility flag is missing"
grep -Fq 'mutation actions are not supported' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperHookRule.java" || fail "shared custom Hook parser has no explicit mutation-action refusal"
grep -Fq 'DeveloperHookRule.isUnsupportedMutationAction(ruleFields[2])' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java" || fail "remote config does not explicitly reject mutation actions"
grep -Fq 'DeveloperHookRule.isUnsupportedMutationAction(actionText)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native custom Hook editor does not explain mutation-action refusal"
grep -q 'android.intent.action.MAIN' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "launcher MAIN action missing"
grep -q 'android.intent.category.LAUNCHER' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "launcher category missing"
grep -q 'QUERY_ALL_PACKAGES' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "installed-app visibility permission missing"
grep -q 'android:windowSoftInputMode="adjustResize"' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "Hook forms do not resize around the on-screen keyboard"
python3 - "$ROOT/fx-patches/merge_hook_single_apk.py" <<'PY'
from pathlib import Path
import sys

generator = Path(sys.argv[1]).read_text(encoding="utf-8")
# The merger uses ElementTree rather than hand-writing XML attributes. Assert
# the exact semantic attribute/value assignment on the unique launcher node,
# and assert it serializes that same mutated manifest tree.
assert 'launcher_activities[0].set(ANDROID + "windowSoftInputMode", "adjustResize")' in generator, (
    "unified APK manifest generator must preserve adjustResize on the launcher Activity"
)
assert 'ET.tostring(manifest_root, encoding="unicode"' in generator, (
    "unified APK manifest generator must serialize the mutated manifest tree"
)
assert 'merged_root = ET.parse(manifest)' in generator, (
    "unified APK manifest generator must reparse the written manifest for verification"
)
print("PASS: unified APK manifest generator retains launcher adjustResize semantics")
PY
grep -q "createNewFile()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "legacy Android export can overwrite an existing file"
grep -q "createUniqueFile(dir, safeName)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "export filename collision handling missing"
grep -q '公共 Download/FX/' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "Android 10+ public export location is not reported accurately"
grep -q '应用专属下载目录' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "pre-Android 10 app-specific export location is not disclosed"
grep -q "if (closed || activity.isFinishing()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "RootBridge does not reject navigation after Activity teardown"
grep -q "if (!closed && !activity.isFinishing()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "queued RootBridge navigation does not recheck Activity lifecycle"
grep -q 'private static boolean isTrustedDocumentUrl(Uri uri)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "WebView main document origin is not allowlisted"
grep -q 'return !request.isForMainFrame() || !isTrustedDocumentUrl(request.getUrl());' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "untrusted iframe can reach the JavaScript root bridge"
grep -q 'if (!isTrustedAssetUrl(uri))' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "off-origin WebView subresources are not blocked"
grep -q "form-action 'none'" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "WebView CSP permits unintended form submissions"
grep -q 'private void refreshHookRemoteStatus(TextView target)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook hub lacks live Remote Files status"
# Interface modes: persisted, validated, reversible, and accurately described.
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
grep -Fq 'getSharedPreferences("fx_ui", MODE_PRIVATE)' "$ACTIVITY" || fail "interface mode is not persisted locally"
grep -Fq 'normalizeUiMode(getSharedPreferences("fx_ui", MODE_PRIVATE)' "$ACTIVITY" || fail "unknown persisted interface modes are not normalized"
grep -Fq 'private String normalizeUiMode(String mode)' "$ACTIVITY" || fail "interface mode validation helper missing"
grep -Fq 'if (settingsUiVisible) { showDashboard(); return; }' "$ACTIVITY" || fail "Back from native Settings does not return to the dashboard"
grep -Fq 'private void applyWebUiMode()' "$ACTIVITY" || fail "WebView interface mode renderer missing"
grep -Fq 'FxDesignModePanelKt.installFxDesignModePanel' "$ACTIVITY" || fail "native Compose design mode panel is not mounted in Settings"
grep -Fq "implementation 'top.yukonga.miuix.kmp:miuix-android:0.7.2'" "$ROOT/adhook/app/build.gradle" || fail "official Miuix Android dependency missing"
grep -Fq "implementation 'io.github.kyant0:backdrop:1.0.0'" "$ROOT/adhook/app/build.gradle" || fail "official Kyant Backdrop dependency missing"
DESIGN_PANEL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt"
grep -Fq 'MiuixTheme(controller = themeController)' "$DESIGN_PANEL" || fail "real Miuix theme is not used"
NATIVE_SHELL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt"
grep -Fq 'MiuixTheme(controller = controller)' "$NATIVE_SHELL" || fail "native app shell must use the Miuix theme"
grep -Fq 'miuixColors.surface' "$NATIVE_SHELL" || fail "Miuix mode must use the real Miuix surface palette"
grep -Fq 'miuixColors.primaryContainer' "$NATIVE_SHELL" || fail "Miuix selected tab must use the real Miuix color scheme"
grep -Fq 'top.yukonga.miuix.kmp.basic.Card' "$DESIGN_PANEL" || fail "real Miuix Card component is not used"
grep -Fq '.drawBackdrop(' "$DESIGN_PANEL" || fail "Backdrop renderer is not used by Liquid Glass mode"
grep -Fq 'lens(18.dp.toPx(), 22.dp.toPx())' "$DESIGN_PANEL" || fail "Backdrop lens refraction effect missing"
grep -Fq '.layerBackdrop(backdrop)' "$DESIGN_PANEL" || fail "Backdrop source layer missing"
grep -Fq 'AndroidView(' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "real page content is not hosted inside Compose shell"
grep -Fq '.layerBackdrop(backdrop)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "actual page is not recorded as Backdrop source"
grep -Fq 'Record the real page beneath' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt" || fail "Backdrop must sample live page content, not a decorative gradient"
if grep -Fq 'backdrop-filter:' "$ACTIVITY"; then fail "WebView CSS still claims to implement the native glass blur"; fi
grep -Fq '"classic".equals(uiMode)' "$ACTIVITY" || fail "classic WebView mode must remain distinct while native Miuix/Glass are not CSS-emulated"
grep -Fq 'Miuix and Liquid Glass' "$ACTIVITY" || fail "native renderer boundary is not documented"
grep -Fq ': ""' "$ACTIVITY" || fail "Miuix/Glass must not be faked through injected WebView CSS"
grep -q 'scripts/status.sh json' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook status reader does not request JSON"
grep -q 'hook_native_notification_permission_hide_enabled' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook hub omits native notification permission-query status"
grep -q 'hook_native_clipboard_isolate_enabled' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook hub omits clipboard isolation status"
grep -q 'hook_native_member_diag_enabled' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook hub omits member diagnostics status"
grep -q 'hook_native_config_found' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook status does not distinguish missing config"
grep -q 'hook_native_wifi_scan_enabled' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook status omits Wi-Fi state"
grep -q 'cancelHookStatusRefresh()' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Hook status worker is not cancelled on screen teardown"
PRIVACY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
grep -Fq '先开启「隐私保护总开关」' "$PRIVACY" || fail "privacy page does not explain the per-app master switch prerequisite"
grep -Fq '只读会员状态诊断不受该总开关控制' "$PRIVACY" || fail "privacy page does not distinguish read-only member diagnostics from privacy master gating"
grep -Fq 'addNativeActionCard("应用内广告标识"' "$PRIVACY" || fail "native privacy page lacks app-scoped advertising identifier entry"
grep -Fq 'addNativeActionCard("剪贴板读取与隔离"' "$PRIVACY" || fail "native privacy page lacks clipboard controls entry"
grep -Fq 'addNativeActionCard("Wi-Fi 扫描保护"' "$PRIVACY" || fail "native privacy page lacks Wi-Fi privacy entry"
grep -Fq 'addNativeActionCard("位置访问保护"' "$PRIVACY" || fail "native privacy page lacks location privacy entry"
grep -Fq 'addNativeActionCard("麦克风保护"' "$PRIVACY" || fail "native privacy page lacks microphone privacy entry"
grep -Fq 'addNativeActionCard("摄像头访问保护"' "$PRIVACY" || fail "native privacy page lacks camera privacy entry"
grep -Fq 'addNativeActionCard("传感器访问与采样"' "$PRIVACY" || fail "native privacy page lacks sensor privacy entry"
grep -Fq 'addNativeActionCard("通知监听与权限提示"' "$PRIVACY" || fail "native privacy page lacks notification privacy entry"
grep -Fq 'addNativeActionCard("媒体查询与 EXIF"' "$PRIVACY" || fail "native privacy page lacks media/EXIF privacy entry"
grep -Fq 'addNativeActionCard("只读会员状态诊断"' "$PRIVACY" || fail "native privacy page lacks read-only diagnostic entry"
# Advanced privacy categories must read the real settings.conf and save through Root/module code.
grep -Fq 'native-privacy-settings.json' "$PRIVACY" || fail "native privacy schema asset is not loaded"
grep -Fq 'native-privacy-settings.sh' "$PRIVACY" || fail "native privacy switches do not use the module-side writer"
grep -Fq 'settings.conf' "$ROOT/fx-patches/native-privacy-settings.sh" || fail "native privacy writer does not target persisted module settings"
grep -Fq 'apply.sh" fast' "$ROOT/fx-patches/native-privacy-settings.sh" || fail "native privacy writer does not request real module apply"
python3 - "$PRIVACY" <<'PY'
import pathlib, sys
s=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start=s.index("private void showNativeSettingsGroup(")
render=s.index("private void renderNativePrivacySettingsGroup(", start)
edit_bridge=s.index("private void loadNativePrivacyEditEntries(", render)
native_methods = {
    "showNativeSettingsGroup": s[start:render],
    "renderNativePrivacySettingsGroup": s[render:edit_bridge],
}
for method, body in native_methods.items():
    for token, message in (
        ("evaluateJavascript", "advanced privacy toggle UI still reads/writes through WebView"),
        ("webView", "advanced privacy toggle UI still depends on WebView lifecycle"),
    ):
        pos = body.find(token)
        assert pos < 0, f"{message} in {method}: {body[max(0, pos-100):pos+180]!r}"
native = "".join(native_methods.values())
assert "runNativeModuleCommand(" in native, "advanced privacy UI is not backed by Root/module commands"
assert "native-privacy-settings.sh" in native and " list" in native, "advanced privacy UI does not read filtered module flags"
bridge=s[edit_bridge:s.index("private void setNativePrivacySetting(", edit_bridge)]
assert 'if (!"vpnPanel".equals(panelId)) return;' in bridge, "edit-only compatibility bridge must be limited to VPN settings"
PY
grep -Fq 'private void showAppList(String privacySection)' "$PRIVACY" || fail "privacy cards cannot open the per-app selector with a category context"
grep -Fq 'private String activePrivacySection;' "$PRIVACY" || fail "privacy navigation context is not retained across editor screens"
grep -Fq 'activePrivacySection = privacySection;' "$PRIVACY" || fail "privacy app picker does not retain the selected category"
grep -Fq 'boolean hookToolsPage = "自定义 Hook".equals(activePrivacySection);' "$PRIVACY" || fail "Dia custom Hook origin is not distinguished from Privacy origin"
grep -Fq 'selectedBottomTab = activePrivacySection == null || hookToolsPage ? 4 : 2;' "$PRIVACY" || fail "Privacy-origin configuration must keep the Privacy tab selected while Dia custom Hook remains on Hook"
grep -Fq 'outState.putBoolean("fx_hook_screen_visible", hookUiVisible);' "$PRIVACY" || fail "native Hook editor visibility is not saved independently of the selected tab"
grep -Fq 'state.getBoolean("fx_hook_screen_visible", selectedBottomTab == 4)' "$PRIVACY" || fail "native Hook editor is not restored when the Privacy tab remains selected"
grep -Fq 'outState.putString("fx_privacy_section", activePrivacySection)' "$PRIVACY" || fail "originating Privacy category is not saved across Activity recreation"
grep -Fq 'showAppList(activePrivacySection);' "$PRIVACY" || fail "restored Privacy editor does not reopen its original category"
grep -Fq 'final String requested = activePrivacySection;' "$PRIVACY" || fail "per-app editor rebuilds do not restore the active privacy section"
grep -Fq 'showAppList(activePrivacySection)' "$PRIVACY" || fail "return navigation loses the originating privacy category"
grep -Fq 'private void focusPendingPrivacySection()' "$PRIVACY" || fail "privacy category does not deep-link to its native controls"
grep -Fq 't.setTag("fx-section:" + s);' "$PRIVACY" || fail "native Hook section headers cannot be targeted for category navigation"
grep -Fq 'section("标识与追踪")' "$PRIVACY" || fail "per-app identifier controls are not grouped"
grep -Fq 'section("剪贴板保护")' "$PRIVACY" || fail "per-app clipboard controls are not grouped"
grep -Fq 'section("Wi-Fi 网络隐私")' "$PRIVACY" || fail "per-app Wi-Fi privacy controls are not grouped"
grep -Fq 'section("位置隐私")' "$PRIVACY" || fail "per-app location privacy controls are not grouped"
grep -Fq '() -> showAppList("Wi-Fi 网络隐私")' "$PRIVACY" || fail "Wi-Fi privacy card does not focus its own controls"
grep -Fq '() -> showAppList("位置隐私")' "$PRIVACY" || fail "location privacy card does not focus its own controls"

grep -Fq 'addNativeActionCard("应用内广告标识"' "$PRIVACY" || fail "advertising identifier card does not match the implemented app-scoped control"
grep -Fq '不修改 Android ID 或系统广告设置' "$PRIVACY" || fail "advertising identifier card overclaims Android ID coverage"
grep -Fq 'addNativeActionCard("Wi-Fi 扫描保护"' "$PRIVACY" || fail "Wi-Fi card title overclaims network identifier coverage"
grep -Fq '不拦截网络连接、DNS、VPN 或套接字流量' "$PRIVACY" || fail "Wi-Fi card omits the actual API scope limitation"
if grep -Fq 'section("网络与位置")' "$PRIVACY"; then fail "legacy combined Wi-Fi/location section remains"; fi
grep -Fq 'section("设备访问")' "$PRIVACY" || fail "per-app microphone/camera controls are not grouped"
grep -Fq 'section("媒体隐私")' "$PRIVACY" || fail "per-app media/EXIF controls are not grouped"
python3 - "$PRIVACY" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
mic = s.index('section("麦克风保护")')
mic_block = s[mic:s.index('section("通知保护")', mic)]
assert '"mic_access_block"' in mic_block, "microphone startup blocking is outside the microphone section"
assert '"mic_silence"' in mic_block, "microphone silence control is outside the microphone section"
device = s[s.index('section("设备访问")'):s.index('section("媒体隐私")')]
assert '"camera_access_block"' in device, "camera access control is missing from Device access"
assert '"mic_access_block"' not in device, "microphone control is duplicated in Device access"
PY
grep -Fq '() -> showAppList("标识与追踪")' "$PRIVACY" || fail "identifier card does not focus identifier controls"
grep -Fq '() -> showAppList("媒体隐私")' "$PRIVACY" || fail "media card does not focus media controls"
grep -Fq 'nativeScroll.smoothScrollTo(0, Math.max(0, child.getTop() - dp(12)))' "$PRIVACY" || fail "privacy deep-link does not scroll to the relevant native control group"
grep -Fq '() -> showAppList("麦克风保护")' "$PRIVACY" || fail "microphone privacy entry is not category-routed"
grep -Fq '() -> showAppList("传感器保护")' "$PRIVACY" || fail "sensor privacy entry is not category-routed"
grep -Fq '() -> showAppList("通知保护")' "$PRIVACY" || fail "notification privacy entry is not category-routed"
grep -Fq 'this::showAppList' "$PRIVACY" || fail "privacy entries are not connected to per-app native configuration"

[ -s "$APK" ] || fail "built Hook APK missing"
CHECK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/fx-hook-apk-check.XXXXXX")" || fail "cannot create temporary APK check directory"
trap 'rm -rf "$CHECK_TMP"' EXIT HUP INT TERM
# Inspect extracted files directly. Piping large command substitutions into grep -q
# closes the pipe early and causes noisy printf EPIPE errors under dash.
WEBUI_FILE="$CHECK_TMP/webroot.html"
unzip -p "$APK" assets/webroot/index.html > "$WEBUI_FILE" || fail "embedded WebUI cannot be extracted"
NATIVE_PRIVACY_SCHEMA="$CHECK_TMP/native-privacy-settings.json"
unzip -p "$APK" assets/native-privacy-settings.json > "$NATIVE_PRIVACY_SCHEMA" || fail "native privacy settings schema missing from APK"
python3 - "$NATIVE_PRIVACY_SCHEMA" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
panels=data.get("panels", [])
assert data.get("schema_version")==1
expected = {
    "vpnPanel", "rootPanel", "advPanel", "netPanel", "permPanel", "sensorPanel",
    "locationPanel", "devicePanel", "mediaPanel", "filePanel", "notifyPanel",
    "kernelPanel", "miscPanel",
}
actual = {p.get("id") for p in panels}
assert actual == expected, "APK native settings schema is incomplete: missing=" + repr(sorted(expected-actual)) + " unexpected=" + repr(sorted(actual-expected))
assert len(panels)==13, "APK native settings schema must contain VPN plus 12 privacy panels"
keys=[item.get("key") for p in panels for item in p.get("items", [])]
assert len(keys)==112, "APK native VPN/privacy control count is incomplete: %d" % len(keys)
assert len(keys)==len(set(keys)), "APK native VPN/privacy settings contain duplicate keys"
assert all(p.get("items") for p in panels), "APK contains an empty native settings panel"
PY
grep -Fq 'data-tab="ad"' "$WEBUI_FILE" || fail "embedded WebUI Ad compatibility tab missing"
grep -Fq "document.getElementById('pageHosts').classList.toggle('on',t==='ad')" "$WEBUI_FILE" || fail "embedded Ad tab no longer activates merged Hosts content"
grep -Fq 'id="pageHosts"' "$WEBUI_FILE" || fail "embedded merged Hosts page missing"
asset_entry_count=$(unzip -Z1 "$APK" | grep -xc 'assets/webroot/index.html' || true)
[ "$asset_entry_count" -eq 1 ] || fail "APK contains $asset_entry_count copies of assets/webroot/index.html"
if grep -Fq 'id="cardFxAdHook"' "$WEBUI_FILE"; then
  echo "DEBUG: legacy Hook card remains in extracted APK WebUI:"
  grep -n -C 2 'id="cardFxAdHook"' "$WEBUI_FILE" | head -30
  if ! cmp -s "$ROOT/adhook/app/src/main/assets/webroot/index.html" "$WEBUI_FILE"; then
    echo "DEBUG: APK WebUI differs from the staged source asset:"
    sha256sum "$ROOT/adhook/app/src/main/assets/webroot/index.html" "$WEBUI_FILE"
  fi
  fail "duplicate WebUI LSPosed manager card remains in APK"
fi
! grep -Fq 'id="fxHookDialog"' "$WEBUI_FILE" || fail "legacy WebUI Hook target dialog remains in APK"
! grep -Fq 'id="fx-lsposed-ad-hook-controller"' "$WEBUI_FILE" || fail "legacy WebUI Hook controller remains in APK"
! grep -Fq 'id="fxHookManage"' "$WEBUI_FILE" || fail "legacy WebUI Hook entry button remains in APK"
grep -Fq 'id="cardHook"' "$WEBUI_FILE" || fail "separate UID network-blocking Hook card was removed"
[ -x "$AAPT" ] || fail "Android aapt missing"
BADGING_FILE="$CHECK_TMP/badging.txt"
"$AAPT" dump badging "$APK" > "$BADGING_FILE"
grep -q "^package: name='de.privacyguard.adhook'" "$BADGING_FILE" || fail "unexpected package id"
grep -q "^launchable-activity:" "$BADGING_FILE" || fail "APK has no launcher activity"
grep -q "uses-permission: name='android.permission.QUERY_ALL_PACKAGES'" "$BADGING_FILE" || fail "APK package visibility permission absent"
# Verify the actual APK, not just source-tree declarations, contains both LSPosed entrypoints.
LEGACY_INIT="$(unzip -p "$APK" assets/xposed_init 2>/dev/null || true)"
printf '%s\n' "$LEGACY_INIT" | grep -Fxq 'de.privacyguard.hook.MainHook' || fail "legacy MainHook Xposed entrypoint missing from APK"
printf '%s\n' "$LEGACY_INIT" | grep -Fxq 'de.privacyguard.hook.DiaFridaTargetHook' || fail "Dia Frida Xposed target-loader entrypoint missing from APK"
MODERN_INIT="$(unzip -p "$APK" META-INF/xposed/java_init.list 2>/dev/null || true)"
[ "$MODERN_INIT" = "de.privacyguard.adhook.AdVisibilityHook" ] || fail "modern libxposed API entrypoint missing from APK"
MODULE_PROP="$(unzip -p "$APK" META-INF/xposed/module.prop 2>/dev/null || true)"
printf '%s\n' "$MODULE_PROP" | grep -qx 'minApiVersion=101' || fail "modern libxposed minimum API metadata missing"
printf '%s\n' "$MODULE_PROP" | grep -qx 'targetApiVersion=101' || fail "modern libxposed target API metadata missing"
DEX_TMP="$CHECK_TMP/dex"
mkdir -p "$DEX_TMP"
unzip -q "$APK" 'classes*.dex' -d "$DEX_TMP" || fail "APK DEX payload could not be extracted"
for required_class in 'de/privacyguard/hook/MainHook' 'de/privacyguard/hook/DiaFridaTargetHook' 'de/privacyguard/adhook/AdVisibilityHook'; do
  class_found=0
  for dex_file in "$DEX_TMP"/classes*.dex; do
    [ -f "$dex_file" ] || continue
    if strings "$dex_file" | grep -F "$required_class" >/dev/null; then
      class_found=1
      break
    fi
  done
  [ "$class_found" -eq 1 ] || fail "required LSPosed class missing from APK DEX: $required_class"
done
echo "PASS: FX Hook APK contains native launcher plus both legacy Xposed and modern libxposed entrypoints"
# Business controls must remain on their owning primary tabs, never be buried in Settings.
main_activity="adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
privacy_block="$(sed -n '/private void buildNativePrivacyPage()/,/private void refreshNativePrivacyStatus/p' "$main_activity")"
vpn_block="$(sed -n '/private void renderNativePage(/,/private void refreshNativeModuleStatus/p' "$main_activity")"
settings_block="$(python3 - "$main_activity" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
signature = "private void showSettings()"
start = source.index(signature)
depth = 0
for index in range(source.index("{", start), len(source)):
    if source[index] == "{":
        depth += 1
    elif source[index] == "}":
        depth -= 1
        if depth == 0:
            print(source[start:index + 1], end="")
            break
else:
    raise SystemExit("could not isolate showSettings() method")
PY
)"
printf '%s' "$privacy_block" | grep -q 'addNativeSettingsCategory("传感器", "sensorPanel")'
printf '%s' "$privacy_block" | grep -q 'addNativeSettingsCategory("通知与剪贴板", "notifyPanel")'
printf '%s' "$vpn_block" | grep -q 'addNativeSettingsCategory("DNS、分流与连接策略", "vpnPanel")'
if printf '%s' "$settings_block" | grep -Eq 'addNativeSettingsCategory|VPN / DNS|传感器|通知与剪贴板|Root / 模块隐藏'; then
  echo "FAIL: feature settings leaked into the Settings destination" >&2
  exit 1
fi
printf '%s' "$settings_block" | grep -q '界面模式'
# Native Script CRUD, state rollback and QuickJS execution must use module commands, not WebView mutation calls.
grep -Fq 'editNativeScript(index, valueText, note, rows, status)' "$main_activity"
grep -Fq 'private void editNativeScript(int index' "$main_activity"
grep -Fq 'nativeScriptStoreCommand("update"' "$main_activity"
grep -Fq 'nativeScriptStoreCommand("toggle", String.valueOf(index + 1)' "$main_activity"
grep -Fq 'nativeScriptStoreCommand("delete", String.valueOf(index + 1)' "$main_activity"
grep -Fq 'runNativeModuleCommand(command, 30000L, result ->' "$main_activity"
grep -Fq 'restoreNativeScriptSwitch(index, control, previous, rows, status)' "$main_activity"
grep -Fq 'setNativeScriptEnabled(index, checked, rows, status, control, previous)' "$main_activity"
grep -Fq 'setNativeScriptEnabled(index, checked, rows, status, control, enabled)' "$main_activity"
grep -Fq '脚本状态保存失败，已恢复原状态' "$main_activity"
grep -Fq 'if (!valueText.startsWith("https://"))' "$main_activity" || fail "HTTPS subscriptions are incorrectly exposed as local JS execution targets"
grep -Fq 'run.setEnabled(on)' "$main_activity" || fail "disabled local scripts can be launched from the native page"
grep -Fq 'private static String nativeScriptSha256(String value)' "$main_activity"
grep -Fq 'nativeScriptSha256(source)' "$main_activity"
grep -Fq 'private void runNativeLocalScript(int index, String expectedSha256' "$main_activity"
grep -Fq 'local-run.sh' "$main_activity"
# Custom Hook JSON import must restore the prior in-memory rule set if SharedPreferences commit fails.
grep -Fq 'previousRuleState' "$main_activity"
grep -Fq 'hadHookEnabled' "$main_activity"
grep -Fq 'previousGroupSet' "$main_activity"
grep -Fq 'boolean rollbackSaved = rollback.commit();' "$main_activity"
grep -Fq '原有规则已恢复' "$main_activity"

# Rule-group add/rename/delete/move must restore prior assignments if persistence fails.
grep -Fq 'private boolean commitCustomRuleGroupUpdate(' "$main_activity"
grep -Fq 'previousAssignments.put(key' "$main_activity"
grep -Fq 'existingAssignmentKeys.add(key)' "$main_activity"
grep -Fq 'if (hadGroupSet) rollback.putStringSet(groupsKey, previousGroups);' "$main_activity"
grep -Fq 'lastCustomRuleGroupRollbackSaved = rollback.commit();' "$main_activity"
grep -Fq 'return commitCustomRuleGroupUpdate(groups, java.util.Collections.emptyMap());' "$main_activity"
grep -Fq 'return commitCustomRuleGroupUpdate(groups, assignments);' "$main_activity"
grep -Fq 'if (!commitCustomRuleGroupUpdate(groups, assignments))' "$main_activity"
grep -Fq 'if (!commitCustomRuleGroupUpdate(getCustomRuleGroups(), assignments))' "$main_activity"

# Add/rename dialogs keep per-target drafts and reopen after a configuration change.
grep -Fq 'fx_custom_rule_group_dialog_mode' "$main_activity"
grep -Fq 'fx_custom_rule_group_dialog_value' "$main_activity"
grep -Fq 'customRuleGroupDialogRestorePending = customRuleGroupDialogMode != null;' "$main_activity"
grep -Fq 'if (customRuleGroupDialogRestorePending)' "$main_activity"
grep -Fq 'dev_rule_group_add_draft' "$main_activity"
grep -Fq 'dev_rule_group_rename_draft:' "$main_activity"
[ "$(grep -Fc 'new android.text.InputFilter.LengthFilter(24)' "$main_activity")" -eq 2 ] || fail "rule group add/rename inputs must enforce their 24-character name limit"
grep -Fq 'lastCustomRuleGroupCommitAttempted = false;' "$main_activity"
grep -Fq 'lastCustomRuleGroupCommitAttempted = true;' "$main_activity"
grep -Fq 'String reason = lastCustomRuleGroupCommitAttempted' "$main_activity"
grep -Fq '原配置未写入。' "$main_activity"
grep -Fq 'customRuleGroupDialogSlot' "$main_activity"
grep -Fq 'customRuleGroupDialogChoice' "$main_activity"
grep -Fq 'fx_custom_rule_group_dialog_slot' "$main_activity"
grep -Fq 'fx_custom_rule_group_dialog_choice' "$main_activity"
grep -Fq 'showCustomRuleGroupPicker(customRuleGroupDialogSlot, customRuleGroupDialogChoice)' "$main_activity"
grep -Fq 'if ("actions".equals(mode) && value != null)' "$main_activity"
grep -Fq 'if ("delete".equals(mode) && value != null)' "$main_activity"
grep -Fq 'showRenameCustomRuleGroupDialog(value)' "$main_activity"

# Adding a group from the Move Rule picker must return to that exact picker and select the new group.
grep -Fq 'private boolean customRuleGroupReturnToPicker;' "$main_activity"
grep -Fq 'state.getBoolean("fx_custom_rule_group_return_to_picker", false)' "$main_activity"
grep -Fq 'outState.putBoolean("fx_custom_rule_group_return_to_picker",' "$main_activity"
grep -Fq 'customRuleGroupReturnToPicker = true;' "$main_activity"
grep -Fq 'private void cancelCustomRuleGroupAddDialog()' "$main_activity"
grep -Fq 'if (returnToPicker && slot > 0) showCustomRuleGroupPicker(slot, choice);' "$main_activity"
grep -Fq 'showCustomRuleGroupPicker(pickerSlot, preferredIndex);' "$main_activity"
grep -Fq 'retryCustomRuleGroupAddDialog(returnToPicker, pickerSlot, pickerChoice)' "$main_activity"
