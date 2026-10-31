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
grep -q 'pendingWebPage = webPageForBottomTab(lastWebTabIndex);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "restored dashboard tab is not replayed after WebView reload"
grep -q 'webView.destroy();' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Activity destruction does not release the WebView"
grep -q 'fileChooserCallback.onReceiveValue(null);' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "pending document picker callback is not cancelled"
grep -q 'case "pageAd": tab = "ad"; break;' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "native Ad tab does not route to merged Hosts page"
grep -q 'String\[\] labels = {"VPN", "Ad", "隐私", "脚本", "Hook", "设置"};' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "six-item native bottom navigation contract missing"
grep -q "MAX_APP_ROWS_PER_PAGE = 40" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app list is not paginated"
grep -q 'new Thread(() -> {' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "installed app indexing is not moved off the UI thread"
grep -q '"fx-app-index"' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "background app-index worker missing"
grep -q "generation != appLoadGeneration" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "stale app-index result can overwrite a newer screen"
grep -q "appLoader.interrupt()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "app-index worker is not cancelled on Activity destruction"
grep -q "appendAppRows(0, Math.min(MAX_APP_ROWS_PER_PAGE, filtered.size()))" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app list eagerly renders all installed apps"
grep -q "appLabels.get(ai.packageName)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app labels are not cached for search"
grep -q "appIcons.get(ai.packageName)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Hook app icons are not cached between search renders"
grep -q "Locale.ROOT" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "case-insensitive app search is locale-dependent"
grep -q "sym_def_app_icon" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "removed-package icon fallback missing"
grep -q "申请 / 重新检查 Root 权限" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "root authorization action missing"
grep -q "new ProcessBuilder(\"su\", \"-c\", command)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "KernelSU su bridge missing"
grep -Eq "waitFor\(Math\.max\(1000L, timeoutMs\), TimeUnit\.MILLISECONDS\)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "bounded root command timeout missing"
grep -q "destroyForcibly()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootAccess.java" || fail "root timeout process cleanup missing"
grep -q 'RootAccess.execute(command)' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "root config publisher missing"
grep -q 'fx-hook-targets.conf' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "Remote Files target config path missing"
grep -q 'DeveloperHookRule.parse(ruleId+"|"+method+"|OBSERVE|0"' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" || fail "read-only custom rule validation missing"
grep -q 'android.intent.action.MAIN' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "launcher MAIN action missing"
grep -q 'android.intent.category.LAUNCHER' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "launcher category missing"
grep -q 'QUERY_ALL_PACKAGES' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "installed-app visibility permission missing"
grep -q 'android:windowSoftInputMode="adjustResize"' "$ROOT/adhook/app/src/main/AndroidManifest.xml" || fail "Hook forms do not resize around the on-screen keyboard"
grep -q 'android:windowSoftInputMode="adjustResize"' "$ROOT/fx-patches/merge_hook_single_apk.py" || fail "unified APK manifest generator drops keyboard resize behavior"
grep -q "createNewFile()" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "legacy Android export can overwrite an existing file"
grep -q "createUniqueFile(dir, safeName)" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/RootBridge.java" || fail "export filename collision handling missing"
[ -s "$APK" ] || fail "built Hook APK missing"
CHECK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/fx-hook-apk-check.XXXXXX")" || fail "cannot create temporary APK check directory"
trap 'rm -rf "$CHECK_TMP"' EXIT HUP INT TERM
# Inspect extracted files directly. Piping large command substitutions into grep -q
# closes the pipe early and causes noisy printf EPIPE errors under dash.
WEBUI_FILE="$CHECK_TMP/webroot.html"
unzip -p "$APK" assets/webroot/index.html > "$WEBUI_FILE" || fail "embedded WebUI cannot be extracted"
grep -Fq 'data-tab="ad"' "$WEBUI_FILE" || fail "embedded WebUI Ad compatibility tab missing"
grep -Fq "document.getElementById('pageHosts').classList.toggle('on',t==='ad')" "$WEBUI_FILE" || fail "embedded Ad tab no longer activates merged Hosts content"
grep -Fq 'id="pageHosts"' "$WEBUI_FILE" || fail "embedded merged Hosts page missing"
[ -x "$AAPT" ] || fail "Android aapt missing"
BADGING_FILE="$CHECK_TMP/badging.txt"
"$AAPT" dump badging "$APK" > "$BADGING_FILE"
grep -q "^package: name='de.privacyguard.adhook'" "$BADGING_FILE" || fail "unexpected package id"
grep -q "^launchable-activity:" "$BADGING_FILE" || fail "APK has no launcher activity"
grep -q "uses-permission: name='android.permission.QUERY_ALL_PACKAGES'" "$BADGING_FILE" || fail "APK package visibility permission absent"
# Verify the actual APK, not just source-tree declarations, contains both LSPosed entrypoints.
LEGACY_INIT="$(unzip -p "$APK" assets/xposed_init 2>/dev/null || true)"
[ "$LEGACY_INIT" = "de.privacyguard.hook.MainHook" ] || fail "legacy Xposed API entrypoint missing from APK"
MODERN_INIT="$(unzip -p "$APK" META-INF/xposed/java_init.list 2>/dev/null || true)"
[ "$MODERN_INIT" = "de.privacyguard.adhook.AdVisibilityHook" ] || fail "modern libxposed API entrypoint missing from APK"
MODULE_PROP="$(unzip -p "$APK" META-INF/xposed/module.prop 2>/dev/null || true)"
printf '%s\n' "$MODULE_PROP" | grep -qx 'minApiVersion=101' || fail "modern libxposed minimum API metadata missing"
printf '%s\n' "$MODULE_PROP" | grep -qx 'targetApiVersion=101' || fail "modern libxposed target API metadata missing"
DEX_TMP="$CHECK_TMP/dex"
mkdir -p "$DEX_TMP"
unzip -q "$APK" 'classes*.dex' -d "$DEX_TMP" || fail "APK DEX payload could not be extracted"
for required_class in 'de/privacyguard/hook/MainHook' 'de/privacyguard/adhook/AdVisibilityHook'; do
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
