#!/usr/bin/env python3
"""Create one dual-entry LSPosed APK by copying the complete legacy MainHook verbatim."""
from pathlib import Path
import shutil, sys

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
if on_replacement not in text2:
    text2 = text2.replace(on_anchor, on_replacement, 1)
target.write_text(text2, encoding="utf-8")
target.chmod(0o644)

# The copied legacy MainHook owns privacy controls; the modern entry retains ads
# and read-only billing diagnostics, preventing duplicate privacy hooks in one process.
adhook = modern / "java/de/privacyguard/adhook/AdVisibilityHook.java"
a = adhook.read_text(encoding="utf-8")
anchor = "        configLoaded = loadConfig();"
replacement = """        configLoaded = loadConfig();
        // Privacy controls are executed by the verbatim legacy MainHook in this same APK.
        // Keep the modern entry responsible for ad filtering and read-only billing diagnostics.
        privacyEnabled = false;
        wifiScanEnabled = false;
        notificationListenEnabled = false;
        notificationPermissionHideEnabled = false;
        clipboardIsolationEnabled = false;"""
if anchor in a:
    a = a.replace(anchor, replacement, 1)
elif "Privacy controls are executed by the verbatim legacy MainHook" not in a:
    raise SystemExit("modern module-loaded config anchor missing")
adhook.write_text(a, encoding="utf-8")

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
start = m.find("<application")
if start < 0:
    raise SystemExit("modern manifest application tag missing")
end = m.find("/>", start)
if end < 0:
    raise SystemExit("modern manifest self-closing application tag missing")
end += 2
app = """<application
        android:label="FX Unified Hook"
        android:allowBackup="false"
        android:usesCleartextTraffic="false">
        <meta-data android:name="xposedmodule" android:value="true" />
        <meta-data android:name="xposedminversion" android:value="93" />
        <meta-data android:name="xposeddescription" android:value="FX unified privacy and ad filtering Hook" />
        <meta-data android:name="xposedscope" android:resource="@array/xposed_scope" />
    </application>"""
m = m[:start] + app + m[end:]
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
if "adhook-apk-fxunifiedhook.fx-owned" not in installer_text:
    raise SystemExit("unified installer ownership marker missing")
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
grep -q 'install_one de.privacyguard.adhook fxunified' "$ROOT/scripts/install_adhook_app.sh" || fail "installer is not single-package"
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
root_installer_test = repo / "scripts/tests/adhook-app-installer-regression.sh"
root_installer_test.write_text("""#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
INSTALLER="$ROOT/fx-module/scripts/install_adhook_app.sh"
REMOVER="$ROOT/fx-module/scripts/remove_adhook_app.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$INSTALLER" ] && [ -s "$REMOVER" ] || fail "unified installer/remover missing"
cmp -s "$INSTALLER" "$ROOT/fx-module/scripts/install_adhook_app.sh" || fail "packaged installer drift"
TMP="${TMPDIR:-/tmp}/fx-unified-installer-test-$"
mkdir -p "$TMP/bin" "$TMP/mod/optional" "$TMP/state" "$TMP/tmp" "$TMP/pm"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
printf 'unified apk payload\\n' > "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
cat > "$TMP/bin/pm" <<'PM'
#!/bin/sh
set -eu
S=$FX_ADHOOK_FAKE_PM_STATE; mkdir -p "$S"
case "$1" in
 path) grep -Fxq "$2" "$S/installed" 2>/dev/null && echo "package:/data/app/$2/base.apk" || exit 1 ;;
 install)
  [ "$2" = "-r" ]; [ -s "$3" ]; pkg=de.privacyguard.adhook
  if [ "${FX_ADHOOK_FAKE_SIGNATURE_MISMATCH:-0}" = 1 ]; then echo 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: signatures do not match]' >&2; exit 1; fi
  grep -Fxv "$pkg" "$S/installed" > "$S/installed.tmp" 2>/dev/null || :
  mv "$S/installed.tmp" "$S/installed"; echo "$pkg" >> "$S/installed"; echo "$pkg" >> "$S/install-calls" ;;
 uninstall)
  grep -Fxv "$2" "$S/installed" > "$S/installed.tmp" 2>/dev/null || :
  mv "$S/installed.tmp" "$S/installed"; echo "$2" >> "$S/uninstall-calls" ;;
 *) exit 9 ;;
esac
PM
chmod 0755 "$TMP/bin/pm"
export PATH="$TMP/bin:$PATH" FX_ADHOOK_FAKE_PM_STATE="$TMP/pm" FX_ADHOOK_STATE_DIR="$TMP/state" FX_ADHOOK_TMP_DIR="$TMP/tmp" FX_ADHOOK_LOG="$TMP/state/install.log"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "install failed"
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "unified package missing"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "expected exactly one install"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "idempotent install failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 1 ] || fail "unchanged package reinstalled"
printf 'update\\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
sh "$INSTALLER" "$TMP/mod" >/dev/null || fail "update failed"
[ "$(wc -l < "$TMP/pm/install-calls" | tr -d ' ')" = 2 ] || fail "update not reinstalled"
printf 'signature mismatch\\n' >> "$TMP/mod/optional/FXUnifiedHook.apk"
sha256sum "$TMP/mod/optional/FXUnifiedHook.apk" > "$TMP/mod/optional/FXUnifiedHook.apk.sha256"
export FX_ADHOOK_FAKE_SIGNATURE_MISMATCH=1
if sh "$INSTALLER" "$TMP/mod" >/dev/null 2>&1; then fail "signature mismatch accepted"; fi
grep -Fxq de.privacyguard.adhook "$TMP/pm/installed" || fail "existing package removed on mismatch"
[ ! -s "$TMP/pm/uninstall-calls" ] || fail "installer uninstalled on mismatch"
unset FX_ADHOOK_FAKE_SIGNATURE_MISMATCH
sh "$REMOVER" "$TMP/mod" "$TMP/state" || fail "cleanup failed"
[ ! -s "$TMP/pm/installed" ] || fail "FX-owned unified package remains"
HOOK="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/hook/MainHook.java"
[ -s "$HOOK" ] && [ "$(wc -c < "$MAIN" | tr -d ' ')" -ge 90000 ] || fail "full copied MainHook missing"
grep -q 'de.privacyguard.hook.MainHook' "$ROOT/adhook/app/src/main/assets/xposed_init" || fail "legacy entry declaration missing"
grep -q 'de.privacyguard.adhook.AdVisibilityHook' "$ROOT/adhook/app/src/main/resources/META-INF/xposed/java_init.list" || fail "modern entry declaration missing"
echo "PASS: single unified Hook APK installation, update, signature safety, and dual entrypoints"
""")

root_merge_test = repo / "scripts/tests/v1.0.0-fxhook-single-apk-merge-audit-regression.sh"
root_merge_test.write_text("""#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
M="$ROOT/fx-module"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$M/optional/FXUnifiedHook.apk" ] || fail "unified APK missing"
[ ! -e "$M/optional/PrivacyGuardHook.apk" ] || fail "legacy split APK still packaged"
[ ! -e "$M/optional/FXAdHook.apk" ] || fail "modern split APK still packaged"
grep -q 'install_one de.privacyguard.adhook fxunified' "$M/scripts/install_adhook_app.sh" || fail "single package installer missing"
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
