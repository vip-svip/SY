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
            "block_mediastore", "ad_id_unify"));

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
manifest_text = manifest.read_text(encoding="utf-8")
# Update the existing XML tree in place. Rebuilding <application> from a partial
# template used to silently drop migrated Activities, Services, Providers and
# shortcut metadata; preserving the tree avoids losing any component attributes.
import xml.etree.ElementTree as ET
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
manifest_root = ET.fromstring(manifest_text)
application_node = manifest_root.find("application")
if application_node is None:
    raise SystemExit("modern manifest application element missing or malformed")

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID_NAME = "{" + ANDROID_NS + "}name"
ANDROID_LABEL = "{" + ANDROID_NS + "}label"
ANDROID_ALLOW_BACKUP = "{" + ANDROID_NS + "}allowBackup"
ANDROID_CLEAR_TEXT = "{" + ANDROID_NS + "}usesCleartextTraffic"
ANDROID_THEME = "{" + ANDROID_NS + "}theme"
ANDROID_MIN_SDK = "{" + ANDROID_NS + "}minSdkVersion"
ANDROID_VALUE = "{" + ANDROID_NS + "}value"
ANDROID_RESOURCE = "{" + ANDROID_NS + "}resource"

def component_names(tag):
    return [
        node.attrib.get(ANDROID_NAME, "")
        for node in application_node.findall(tag)
        if node.attrib.get(ANDROID_NAME, "")
    ]

retained_activities = component_names("activity")
retained_services = component_names("service")
retained_receivers = component_names("receiver")
retained_providers = component_names("provider")
required_migrated_activities = {
    ".imported.shield.FxYulongShieldActivity",
    ".imported.shield.FxYulongVirusDatabaseActivity",
    ".imported.shield.FxYulongScanActivity",
    ".imported.shield.WhitelistActivity",
    ".imported.shield.WhitelistPickerActivity",
    ".imported.shield.BlacklistActivity",
}
missing_migrated = required_migrated_activities - set(retained_activities)
if missing_migrated:
    raise SystemExit("Source manifest is missing migrated Yulong Shield Activities: "
                     + ", ".join(sorted(missing_migrated)))

# Preserve the previous compatibility floor without reconstructing or replacing
# the rest of the manifest tree.
uses_sdk = manifest_root.find("uses-sdk")
if uses_sdk is not None:
    uses_sdk.attrib[ANDROID_MIN_SDK] = "27"

application_node.attrib[ANDROID_LABEL] = "FX Hook"
application_node.attrib[ANDROID_ALLOW_BACKUP] = "false"
application_node.attrib[ANDROID_CLEAR_TEXT] = "false"
application_node.attrib[ANDROID_THEME] = "@android:style/Theme.Material.Light.NoActionBar"

def set_application_metadata(name, attribute, value):
    node = next(
        (child for child in application_node.findall("meta-data")
         if child.attrib.get(ANDROID_NAME) == name),
        None,
    )
    if node is None:
        node = ET.SubElement(application_node, "meta-data")
    node.attrib[ANDROID_NAME] = name
    node.attrib[attribute] = value

set_application_metadata("xposedmodule", ANDROID_VALUE, "true")
set_application_metadata("xposedminversion", ANDROID_VALUE, "93")
set_application_metadata("xposeddescription", ANDROID_VALUE,
                         "FX unified privacy and ad filtering Hook")
set_application_metadata("xposedscope", ANDROID_RESOURCE, "@array/xposed_scope")

# QUERY_ALL_PACKAGES is needed by the app picker and must remain a top-level
# permission, not an application child. Preserve existing permission attributes.
query_permission = "android.permission.QUERY_ALL_PACKAGES"
permissions = manifest_root.findall("uses-permission")
if not any(node.attrib.get(ANDROID_NAME) == query_permission for node in permissions):
    ET.SubElement(manifest_root, "uses-permission", {ANDROID_NAME: query_permission})

# Preserve the single launcher entry, all original migrated components and
# the accessibility service, and reject duplicate or competing VPN services.
launcher = [
    node for node in application_node.findall("activity")
    if node.attrib.get(ANDROID_NAME) in (".MainActivity", "de.privacyguard.adhook.MainActivity")
    and any(child.tag == "intent-filter" and
            any(action.attrib.get(ANDROID_NAME) == "android.intent.action.MAIN"
                for action in child.findall("action")) and
            any(category.attrib.get(ANDROID_NAME) == "android.intent.category.LAUNCHER"
                for category in child.findall("category"))
            for child in list(node))
]
if len(launcher) != 1:
    raise SystemExit("Unified Hook manifest must retain exactly one FX launcher Activity")
accessibility = [
    node for node in application_node.findall("service")
    if node.attrib.get(ANDROID_NAME) in (
        ".FxAccessibilityService", "de.privacyguard.adhook.FxAccessibilityService")
]
if len(accessibility) != 1:
    raise SystemExit("Unified Hook manifest must retain exactly one FX accessibility service")

for tag, expected in (
    ("activity", retained_activities),
    ("service", retained_services),
    ("receiver", retained_receivers),
    ("provider", retained_providers),
):
    current = component_names(tag)
    missing = sorted(set(expected) - set(current))
    duplicates = sorted(name for name in set(current) if current.count(name) > 1)
    if missing:
        raise SystemExit("Unified Hook manifest dropped migrated " + tag + " components: "
                         + ", ".join(missing))
    if duplicates:
        raise SystemExit("Unified Hook manifest duplicated " + tag + " components: "
                         + ", ".join(duplicates))

vpn_services = [
    node.attrib.get(ANDROID_NAME, "")
    for node in application_node.findall("service")
    if node.attrib.get("{" + ANDROID_NS + "}permission") == "android.permission.BIND_VPN_SERVICE"
]
if vpn_services:
    raise SystemExit("Migration added a second VpnService: " + ", ".join(vpn_services))
if ".imported.shield.FxYulongInstallScanReceiver" not in retained_receivers:
    raise SystemExit("Unified Hook manifest dropped the migrated Yulong install-scan receiver")

manifest.write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    + ET.tostring(manifest_root, encoding="unicode", short_empty_elements=True)
    + "\n",
    encoding="utf-8",
)


# Align the archived APK regression with the single app's explicit FX Hook label.
apk_regression = fx / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh"
if apk_regression.is_file():
    regression_text = apk_regression.read_text(encoding="utf-8")
    regression_lines = regression_text.splitlines()
    changed = False
    for index, line in enumerate(regression_lines):
        if "APK merge does not preserve FX application label" in line:
            regression_lines[index] = line.replace('android:label="FX"', 'android:label="FX Hook"').replace(
                "APK merge does not preserve FX application label",
                "APK merge does not preserve FX Hook application label")
            changed = True
    if changed:
        apk_regression.write_text("\n".join(regression_lines) + "\n", encoding="utf-8")


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
elif (
    'install_one de.privacyguard.adhook fxunified' not in s
    and not ('_slug=fxunifiedhook' in s and 'optional/FXUnifiedHook.apk' in s)
):
    raise SystemExit("installer source is neither the known split-APK form nor the reviewed unified-APK form")
else:
    print("FX installer already targets the single unified Hook APK.")
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
canonical_installer_test = repo / "scripts/tests/adhook-app-installer-regression.sh"
if not canonical_installer_test.is_file():
    raise SystemExit("canonical unified Hook installer regression is missing")
installer_test.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(canonical_installer_test, installer_test)

# The native Hook editor publishes ad_id_unify in the API-101 overlay. Keep
# module status counts aware of the new per-target privacy feature.
status_script = fx / "scripts/status.sh"
if not status_script.is_file():
    raise SystemExit("module status.sh is missing")
status_text = status_script.read_text(encoding="utf-8")
old_privacy_pattern = "privacy=1|exif_strip=1"
new_privacy_pattern = "privacy=1|ad_id_unify=1|exif_strip=1"
if old_privacy_pattern in status_text:
    if status_text.count(old_privacy_pattern) != 2:
        raise SystemExit("unexpected status.sh privacy target patterns")
    status_text = status_text.replace(old_privacy_pattern, new_privacy_pattern)
elif status_text.count(new_privacy_pattern) != 2:
    raise SystemExit("status.sh ad_id_unify privacy accounting is missing or ambiguous")
status_script.write_text(status_text, encoding="utf-8")

canonical_adid_test = repo / "scripts/tests/v1.0.0-fxhook-adid-unify-regression.sh"
packaged_adid_test = fx / "scripts/tests/v1.0.0-fxhook-adid-unify-regression.sh"
if not canonical_adid_test.is_file():
    raise SystemExit("canonical advertising ID regression is missing")
packaged_adid_test.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(canonical_adid_test, packaged_adid_test)
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
