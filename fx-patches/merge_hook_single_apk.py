#!/usr/bin/env python3
"""Create one dual-entry LSPosed APK by copying the complete legacy MainHook verbatim."""
from pathlib import Path
import re, shutil, sys

fx = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
repo = Path(sys.argv[2] if len(sys.argv) > 2 else ".")
legacy = fx / "lsposed/app/src/main"
modern = repo / "adhook/app/src/main"
source = legacy / "java/de/privacyguard/hook/MainHook.java"
if not source.is_file() or source.stat().st_size < 90000:
    raise SystemExit("complete legacy MainHook.java missing or unexpectedly small")
if not (modern / "java/de/privacyguard/adhook/AdVisibilityHook.java").is_file():
    raise SystemExit("modern AdVisibilityHook.java missing")

# Copy the original 96 KB implementation as-is; only update its self-package identity.
target = modern / "java/de/privacyguard/hook/MainHook.java"
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source, target)
text = target.read_text(encoding="utf-8")
text2 = text.replace('private static final String SELF_PKG = "de.privacyguard.hook";',
                     'private static final String SELF_PKG = "de.privacyguard.adhook";')
if text2 == text:
    raise SystemExit("MainHook SELF_PKG identity anchor missing")
# Keep the complete implementation, but fail closed for root-evasion, VPN-state
# concealment, location spoofing, and hardware/telephony identity forgery controls.
guard_anchor = "    private boolean on(String k) {"
guard = """    private static final Set<String> DISABLED_EVASION_KEYS = new HashSet<>(Arrays.asList(
            "hide_su", "hide_magisk", "hide_ksu", "block_rootcheck_libs",
            "hide_sysfs_nodes", "hide_kernel_debug", "fs_attrs", "fs_hide", "fs_rootlist",
            "fs_isolate", "fs_vfs", "block_process_list", "block_pm_query", "block_mounts",
            "hide_mounts", "block_netstats", "block_net_ifaces", "block_cell_info",
            "usagestats_off", "k_task", "app_list", "vpn_hide", "syssvc_hide",
            "block_kernel_version", "patch_spoof", "gnss_spoof", "mock_location",
            "perapp_mock", "gps", "gps_accuracy", "spoof_android_id", "spoof_imei", "spoof_sim", "telephony", "spoof_serial",
            "spoof_hardware", "spoof_baseband", "spoof_brand", "spoof_manufacturer",
            "spoof_model", "spoof_fingerprint", "spoof_bt_mac", "spoof_wifi_mac",
            "spoof_version", "spoof_storage", "spoof_screen", "spoof_battery",
            "cam_hw_hide", "hide_face_hw", "hide_fingerprint_hw", "mic_hw_hide"));

"""
if guard_anchor in text2 and "DISABLED_EVASION_KEYS" not in text2:
    text2 = text2.replace(guard_anchor, guard + guard_anchor, 1)
on_anchor = "    private boolean on(String k) {"
on_replacement = on_anchor + """
        if (DISABLED_EVASION_KEYS.contains(k)) return false;"""
# Load the per-package API-101 feature ownership map so legacy API-82 hooks
# do not install a second interceptor for features now executed by AdVisibilityHook.
managed_field_anchor = '    private static final String CONF_PATH = "/data/local/tmp/privacyguard/xposed.conf";'
managed_field = managed_field_anchor + '\n    private static final String API101_MANAGED_PATH = "/data/local/tmp/privacyguard/fx-api101-managed.conf";'
if managed_field_anchor not in text2:
    raise SystemExit("legacy config path anchor missing")
text2 = text2.replace(managed_field_anchor, managed_field, 1)

scope_anchor = '    private final List<String> scopeAllow = new ArrayList<>();'
scope_replacement = scope_anchor + '\n    private final Set<String> api101Managed = new HashSet<>();\n    private boolean api101OwnershipAvailable;'
if scope_anchor not in text2:
    raise SystemExit("legacy scope field anchor missing")
text2 = text2.replace(scope_anchor, scope_replacement, 1)

# Load ownership before parsing the optional legacy config. The legacy config
# may be absent on a clean install; duplicate suppression must still be active.
# Load ownership at the start of the config-loading method, before any early
# return for a missing or unreadable legacy xposed.conf. Locate the nearest
# enclosing Java method from the stable post-read anchor rather than assuming
# the legacy method's historical name or return type.
load_anchor = '            r.close();\n            loadApi101Managed();\n            // 档位解析：profile'
if load_anchor in text2:
    text2 = text2.replace(load_anchor, '            r.close();\n            // 档位解析：profile', 1)
close_anchor = '            r.close();\n            // 档位解析：profile'
close_pos = text2.find(close_anchor)
if close_pos < 0:
    raise SystemExit("legacy config parse completion anchor missing")
load_method = re.search(r'(?m)^([ \t]*(?:private|public|protected)\s+(?:static\s+)?(?:synchronized\s+)?(?:boolean|void)\s+loadConf\s*\([^)]*\)(?:\s*throws\s+[^{]+)?\s*\{)', text2)
if not load_method:
    raise SystemExit("legacy loadConf method declaration missing (including optional throws clause)")
load_injection = load_method.group(0) + "\n        loadApi101Managed();"
if "loadApi101Managed();" not in text2[load_method.end():load_method.end()+100]:
    text2 = text2[:load_method.start()] + load_injection + text2[load_method.end():]

helper_anchor = '    private static final Set<String> DISABLED_EVASION_KEYS'
helper = """    private static final Set<String> API101_OWNED_LEGACY_KEYS = new HashSet<>(Arrays.asList(
            "exif_strip", "clipboard", "clipboard_isolate",
            "sensor_accel", "sensor_gyro", "sensor_light", "sensor_magnet",
            "sensor_pressure", "sensor_prox", "sensor_rate_limit",
            "block_wifi_scan", "block_notif_listen", "hide_notif_perm",
            "mic_block", "audio_fp_block", "cam_null", "disable_passive_loc",
            "block_mediastore"));

    private void loadApi101Managed() {
        api101Managed.clear();
        api101OwnershipAvailable = false;
        File managed = new File(API101_MANAGED_PATH);
        if (!managed.isFile() || !managed.canRead()) {
            log("API-101 ownership map unreadable; overlapping legacy hooks disabled for safety");
            return;
        }
        try {
            BufferedReader reader = new BufferedReader(new FileReader(managed));
            try {
                String line;
                while ((line = reader.readLine()) != null) {
                    String[] parts = line.trim().split(",", -1);
                    if (parts.length < 2 || !parts[0].matches("[A-Za-z][A-Za-z0-9_]*(\\\\.[A-Za-z0-9_]+)+")) continue;
                    for (int i = 1; i < parts.length; i++) {
                        String key = parts[i].trim();
                        if (key.matches("[a-z0-9_]{1,64}")) api101Managed.add(parts[0] + "|" + key);
                    }
                }
            } finally {
                reader.close();
            }
            api101OwnershipAvailable = true;
        } catch (IOException e) {
            api101Managed.clear();
            api101OwnershipAvailable = false;
            log("API-101 ownership map read failed; overlapping legacy hooks disabled for safety");
        }
    }

"""
if helper_anchor not in text2:
    raise SystemExit("legacy disabled-key set insertion anchor missing")
text2 = text2.replace(helper_anchor, helper + helper_anchor, 1)

on_anchor = '    private boolean on(String k) {'
on_replacement = on_anchor + """
        if (api101Managed.contains(pkg + "|" + k)) return false;
        if (!api101OwnershipAvailable && API101_OWNED_LEGACY_KEYS.contains(k)) return false;
        if (DISABLED_EVASION_KEYS.contains(k)) return false;"""
if on_anchor not in text2:
    raise SystemExit("legacy on() feature gate anchor missing")
text2 = text2.replace(on_anchor, on_replacement, 1)

if on_replacement not in text2:
    text2 = text2.replace(on_anchor, on_replacement, 1)
target.write_text(text2, encoding="utf-8")
target.chmod(0o644)

# The API-101 runtime owns the per-app privacy features published by the native
# Hook UI. The legacy API-82 entrypoint remains for unmigrated global controls;
# its overlapping keys are masked per package by the ownership file published
# alongside fx-hook-targets.conf (see the MainHook patch below).
adhook = modern / "java/de/privacyguard/adhook/AdVisibilityHook.java"
a = adhook.read_text(encoding="utf-8")
if "configLoaded = loadConfig();" not in a:
    raise SystemExit("modern module-loaded config anchor missing")
# Keep a source copy inside the module archive without importing CI integration
# templates (some are awk fragments intentionally not executable as shell scripts).
module_main = fx / "adhook/app/src/main/java/de/privacyguard/hook/MainHook.java"
module_main.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(target, module_main)

(modern / "assets").mkdir(parents=True, exist_ok=True)
(modern / "res/values").mkdir(parents=True, exist_ok=True)
shutil.copy2(legacy / "assets/xposed_init", modern / "assets/xposed_init")
shutil.copy2(legacy / "res/values/arrays.xml", modern / "res/values/arrays.xml")

gradle = repo / "adhook/app/build.gradle"
g = gradle.read_text(encoding="utf-8")
g = g.replace("minSdk 28", "minSdk 27")
if "de.robv.android.xposed:api:82" not in g:
    g = g.replace("compileOnly 'io.github.libxposed:api:101.0.1'",
                  "compileOnly 'io.github.libxposed:api:101.0.1'\n    compileOnly 'de.robv.android.xposed:api:82'")
if "de.robv.android.xposed:api:82" not in g:
    raise SystemExit("could not add legacy Xposed compileOnly dependency")
gradle.write_text(g, encoding="utf-8")

manifest = modern / "AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8").replace('android:minSdkVersion="28"', 'android:minSdkVersion="27"')
# Replace the complete application element. Cutting at the first "/>" is
# incorrect once the launcher activity contains a self-closing child element.
app_match = re.search(r"<application\b[^>]*>.*?</application>", m, re.S)
if not app_match:
    raise SystemExit("modern manifest application element missing or unbalanced")
# Preserve the APK's native launcher UI while adding the LSPosed metadata.
if 'android.permission.QUERY_ALL_PACKAGES' not in m:
    m = m.replace('<application', '<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES" />\\n    <application', 1)
app = """<application
        android:label="FX"
        android:allowBackup="false"
        android:usesCleartextTraffic="false"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="unspecified">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service
            android:name=".FxAccessibilityService"
            android:label="FX 可选辅助服务"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/fx_accessibility_service" />
        </service>
        <meta-data android:name="xposedmodule" android:value="true" />
        <meta-data android:name="xposedminversion" android:value="93" />
        <meta-data android:name="xposeddescription" android:value="FX unified privacy and ad filtering Hook" />
        <meta-data android:name="xposedscope" android:resource="@array/xposed_scope" />
    </application>"""
m = m[:app_match.start()] + app + m[app_match.end():]
manifest.write_text(m, encoding="utf-8")

# The final module payload must contain only the unified APK, never the old split APKs.
for obsolete in (
    fx / "optional/PrivacyGuardHook.apk",
    fx / "optional/PrivacyGuardHook.apk.sha256",
    fx / "optional/FXAdHook.apk",
    fx / "optional/FXAdHook.apk.sha256",
    fx / "optional/FXAdHook-BUILD-INFO.txt",
):
    obsolete.unlink(missing_ok=True)

# Install one package. Retire the old FX-managed legacy package only after the unified
# package is installed; never uninstall a pre-existing app without our ownership marker.
installer = fx / "scripts/install_adhook_app.sh"
s = installer.read_text(encoding="utf-8")
old = 'install_one de.privacyguard.hook privacyguardhook "$MODDIR/optional/PrivacyGuardHook.apk" || _result=1\ninstall_one de.privacyguard.adhook fxadhook "$MODDIR/optional/FXAdHook.apk" || _result=1'
new = '''install_one de.privacyguard.adhook fxunified "$MODDIR/optional/FXUnifiedHook.apk" || _result=1
if [ "$_result" = 0 ] && package_present de.privacyguard.hook; then
  _old_owned="$STATE_DIR/adhook-apk-privacyguardhook.fx-owned"
  if [ -s "$_old_owned" ]; then
    if pm uninstall de.privacyguard.hook >> "$LOG" 2>&1; then
      rm -f "$STATE_DIR/adhook-apk-privacyguardhook.sha256" "$_old_owned" 2>/dev/null || :
      log_msg "retired previous FX-managed split legacy Hook after unified APK installation"
    else
      log_msg "WARN: could not retire previous FX-managed legacy Hook; unified Hook remains installed"
    fi
  else
    log_msg "leaving pre-existing legacy Hook package untouched: de.privacyguard.hook"
  fi
fi'''
if old in s:
    s = s.replace(old, new)
elif 'install_one de.privacyguard.adhook fxunified' not in s:
    raise SystemExit("installer dual-APK install anchors missing")
installer.write_text(s, encoding="utf-8")

# The package workflow restores the published module archive before applying
# this merge. Always overlay the reviewed repository installers after source
# restoration; otherwise the ZIP silently ships the archive's older installer
# and remover even though repository-level tests exercise the newer scripts.
repo_scripts = repo / "scripts"
repo_scripts.mkdir(parents=True, exist_ok=True)
for helper in ("install_adhook_app.sh", "remove_adhook_app.sh"):
    reviewed = repo_scripts / helper
    if not reviewed.is_file() or reviewed.stat().st_size < 500:
        raise SystemExit(f"reviewed repository helper missing or unexpectedly small: {reviewed}")
    shutil.copy2(reviewed, fx / "scripts" / helper)

# The packaged remover must recognize the same ownership markers written by
# the packaged installer. Guard this invariant before creating the artifact.
installer_text = (fx / "scripts/install_adhook_app.sh").read_text(encoding="utf-8")
remover_text = (fx / "scripts/remove_adhook_app.sh").read_text(encoding="utf-8")
if "_slug=fxunifiedhook" not in installer_text or "$_owned" not in installer_text:
    raise SystemExit("unified installer ownership marker construction missing")
if "fxunifiedhook" not in remover_text:
    raise SystemExit("unified remover ownership marker missing")
if "optional/FXUnifiedHook.apk" not in installer_text:
    raise SystemExit("unified APK install path missing")

# Rewrite focused regressions to assert one APK and both preserved entrypoints.
(fx / "scripts/tests/v1.0.0-fxhook-single-apk-merge-audit-regression.sh").write_text("""#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ROOT/optional/FXUnifiedHook.apk" ] || fail "unified APK missing"
[ ! -e "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "split legacy APK still packaged"
[ ! -e "$ROOT/optional/FXAdHook.apk" ] || fail "split modern APK still packaged"
grep -q 'de.privacyguard.adhook' "$ROOT/adhook/app/build.gradle" 2>/dev/null || :
grep -q 'de.robv.android.xposed:api:82' "$ROOT/../adhook/app/build.gradle" 2>/dev/null || :
[ -s "$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java" ] || fail "original full MainHook source missing"
[ "$(wc -c < "$ROOT/lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java" | tr -d ' ')" -ge 90000 ] || fail "MainHook source unexpectedly truncated"
grep -q '_slug=fxunifiedhook' "$ROOT/scripts/install_adhook_app.sh" || fail "single package installer missing"
grep -q 'optional/FXUnifiedHook.apk' "$ROOT/scripts/install_adhook_app.sh" || fail "unified APK install path missing"
echo "PASS: one APK contains the copied full legacy Hook and modern ad Hook entrypoints"
""")
installer_test = fx / "scripts/tests/adhook-app-installer-regression.sh"
installer_test.write_text("""#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
INSTALLER="$ROOT/scripts/install_adhook_app.sh"; REMOVER="$ROOT/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
TMP="${TMPDIR:-/tmp}/fx-unified-installer-test-$$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'fake unified apk payload\\n' > "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
S=$FX_ADHOOK_FAKE_PM_STATE; mkdir -p "$S"
case "$1" in
 path) grep -Fxq "$2" "$S/installed" 2>/dev/null && echo "package:/data/app/$2/base.apk" || exit 1 ;;
 install)
  [ "$2" = "-r" ]; apk=$3; [ -s "$apk" ]; pkg=de.privacyguard.adhook
  if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi
  grep -Fxv "$pkg" "$S/installed" > "$S/installed.tmp" 2>/dev/null || :
  mv "$S/installed.tmp" "$S/installed"; echo "$pkg" >> "$S/installed"; echo "$pkg" >> "$S/install-calls" ;;
 uninstall) pkg=$2; grep -Fxv "$pkg" "$S/installed" > "$S/installed.tmp" 2>/dev/null || :; mv "$S/installed.tmp" "$S/installed"; echo "$pkg" >> "$S/uninstall-calls" ;;
 *) exit 9 ;;
esac
PM
chmod 0755 "$TMP/bin/pm"
export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "first unified install failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified package not installed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "expected exactly one package install"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged APK reinstalled"
printf 'updated payload\\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "APK update failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 2 ] || fail "updated APK not reinstalled"
printf 'different key\\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch should fail"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed after signature mismatch"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "installer uninstalled package after signature mismatch"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "unified package cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "FX-managed unified package not removed"
echo "PASS: unified Hook APK installs and updates idempotently with signature-safe rollback"
""")
# Replace old APK test path/metadata assertions while retaining its feature-marker checks.
adtest = fx / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh"
s = adtest.read_text(encoding="utf-8")
s = s.replace('optional/FXAdHook.apk', 'optional/FXUnifiedHook.apk')
s = s.replace('FXAdHook-BUILD-INFO.txt', 'FXUnifiedHook-BUILD-INFO.txt')
s = s.replace('if unzip -l "$APK" | grep -q \'assets/xposed_init\'; then fail "legacy and modern Xposed APIs must not be mixed"; fi',
'''unzip -p "$APK" assets/xposed_init 2>/dev/null | grep -qx 'de.privacyguard.hook.MainHook' || fail "copied legacy MainHook entrypoint missing"
unzip -p "$APK" META-INF/xposed/java_init.list 2>/dev/null | grep -qx 'de.privacyguard.adhook.AdVisibilityHook' || fail "modern ad Hook entrypoint missing"
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" ] || fail "copied MainHook source missing"
[ "$(wc -c < "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" | tr -d ' ')" -ge 90000 ] || fail "copied MainHook source truncated"''')
s = s.replace('grep -Eq \'Modern LSPosed API 101|modern libxposed / LSPosed API 101\' \'$INFO\'', 'grep -Fq \'Dual entrypoints: legacy Xposed API 93+ and modern libxposed API 101\' \'$INFO\'')
s = "\n".join(
    'grep -Fq \'Dual entrypoints: legacy Xposed API 93+ and modern libxposed API 101\' "$INFO"' 
    if "grep -E" in line and "API 101" in line else line
    for line in s.splitlines()
) + "\n"
s = s.replace('[ -s "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "legacy Hook APK missing from optional app payload"\n[ -s "$ROOT/optional/PrivacyGuardHook.apk.sha256" ] || fail "legacy Hook APK checksum missing"\n[ "$(sha256sum "$ROOT/optional/PrivacyGuardHook.apk" | awk \'{print $1}\')" = "$(awk \'NR==1 {print $1}\' "$ROOT/optional/PrivacyGuardHook.apk.sha256")" ] || fail "legacy Hook APK checksum mismatch"',
'''unzip -p "$APK" AndroidManifest.xml >/dev/null 2>&1 || fail "unified APK manifest missing"
[ ! -e "$ROOT/optional/PrivacyGuardHook.apk" ] || fail "split legacy APK should not be packaged"''')
s = s.replace('FXAdHook must not require system overlay mount', 'FXUnifiedHook must not require system overlay mount')
s = s.replace('FXAdHook APK archive', 'FX unified Hook APK archive')
adtest.write_text(s, encoding="utf-8")

# Repository-level CI tests execute outside fx-module, so update those guards too.
# Keep the repository-level installer regression intact; it covers ownership-safe removal and stale markers.
root_merge_test = repo / "scripts/tests/v1.0.0-fxhook-single-apk-merge-audit-regression.sh"
root_merge_test.write_text("""#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
M="$ROOT/fx-module"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$M/optional/FXUnifiedHook.apk" ] || fail "unified APK missing"
[ ! -e "$M/optional/PrivacyGuardHook.apk" ] || fail "legacy split APK still packaged"
[ ! -e "$M/optional/FXAdHook.apk" ] || fail "modern split APK still packaged"
grep -q '_slug=fxunifiedhook' "$M/scripts/install_adhook_app.sh" || fail "single package installer missing"
grep -q 'optional/FXUnifiedHook.apk' "$M/scripts/install_adhook_app.sh" || fail "unified APK install path missing"
[ -s "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" ] || fail "copied MainHook missing"
[ "$(wc -c < "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" | tr -d ' ')" -ge 90000 ] || fail "MainHook was truncated"
grep -q 'de.privacyguard.hook.MainHook' "$ROOT/adhook/app/src/main/assets/xposed_init" || fail "legacy entrypoint missing"
grep -q 'de.privacyguard.adhook.AdVisibilityHook' "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "modern entrypoint missing"
grep -q 'DISABLED_EVASION_KEYS.contains(k)' "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" || fail "unsafe evasion/identity toggles are not fail-closed"
grep -q '"gps_accuracy"' "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" || fail "GPS accuracy spoof control is not fail-closed"
grep -q '"spoof_android_id"' "$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java" || fail "Android ID spoof control is not fail-closed"
echo "PASS: legacy MainHook and modern ad Hook are packaged through one APK"
""")

print(f"Unified LSPosed project prepared: copied {target.stat().st_size} bytes of MainHook.java into one APK project.")
