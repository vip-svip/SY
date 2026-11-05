#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE="${1:-$ROOT/fx-module}"
ASSETS="${TMPDIR:-/tmp}/fx-native-privacy-assets-$$"
TMP="${TMPDIR:-/tmp}/fx-native-privacy-test-$$"
fail(){ echo "FAIL: $*" >&2; exit 1; }
trap 'rm -rf "$ASSETS" "$TMP"' EXIT HUP INT TERM
# This regression has two tiers: always validate app-side status wiring; only
# run module mutation/rollback checks when the restored release archive exists.
python3 - "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private void refreshNativePrivacyStatus(TextView target)")
end = source.index("\n    private ", start + 1)
method = source[start:end]
for required in (
    'json.has("root")',
    '"未知（状态接口未提供）"',
    'isAccessibilityEnabled()',
    'FxAccessibilityService.isConnected()',
    'getBoolean("service_connected", false)',
    'getInt("service_pid", -1) == android.os.Process.myPid()',
    '"\\nAccessibility：" + accessibilityStatus',
):
    assert required in method, "privacy authorization summary missing live-state contract: " + required
assert 'json.optBoolean("root", false) ? "已授权" : "未授权"' in method, \
    "reported Root state must remain distinct from unavailable Root state"
print("PASS: privacy authorization summary distinguishes unknown Root state and reports system-enabled/FX-connected Accessibility state")
PY

if [ ! -s "$MODULE/webroot/index.html" ] || [ ! -s "$MODULE/scripts/default.conf" ]; then
  echo "SKIP: module-backed privacy writer checks require restored FX module archive; app-side status contract passed."
  exit 0
fi
if [ ! -s "$MODULE/webroot/index.html" ] || [ ! -s "$MODULE/scripts/default.conf" ]; then
python3 - "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private void refreshNativePrivacyStatus(TextView target)")
end = source.index("\n    private ", start + 1)
method = source[start:end]
for required in (
    'json.has("root")',
    '"未知（状态接口未提供）"',
    'isAccessibilityEnabled()',
    'FxAccessibilityService.isConnected()',
    'getBoolean("service_connected", false)',
    'getInt("service_pid", -1) == android.os.Process.myPid()',
    '"\\\\nAccessibility：" + accessibilityStatus',
):
    assert required in method, "privacy authorization summary missing live-state contract: " + required
assert 'json.optBoolean("root", false) ? "已授权" : "未授权"' in method, \\
    "reported Root state must remain distinct from unavailable Root state"
print("PASS: privacy authorization summary distinguishes unknown Root state and reports system-enabled/FX-connected Accessibility state")
PY
  echo "SKIP: module-backed privacy settings behavior requires restored FX module archive; static authorization checks passed."
  exit 0
fi
[ -s "$MODULE/webroot/index.html" ] || fail "complete module WebUI source missing"
[ -s "$MODULE/scripts/default.conf" ] || fail "module default.conf missing"
[ -s "$ROOT/scripts/native-vpn-config.sh" ] || fail "canonical native VPN config writer missing"
install -D -m 0755 "$ROOT/scripts/native-vpn-config.sh" "$MODULE/scripts/native-vpn-config.sh"
python3 "$ROOT/fx-patches/patch_native_privacy_settings.py" "$MODULE" "$ASSETS"
python3 - "$ASSETS/native-privacy-settings.json" "$MODULE/scripts/default.conf" <<'PY'
import json, re, sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
expected={"vpnPanel","rootPanel","advPanel","netPanel","permPanel","sensorPanel","locationPanel","devicePanel","mediaPanel","filePanel","notifyPanel","kernelPanel","miscPanel"}
panels=data.get("panels",[])
assert data.get("schema_version")==1
assert {p["id"] for p in panels}==expected
assert all(p["items"] for p in panels), "empty native settings category"
keys=[item["key"] for panel in panels for item in panel["items"]]
assert len(keys)>=20, len(keys)
assert len(keys)==len(set(keys)), "duplicate setting keys"
defaults=set()
for line in open(sys.argv[2], encoding="utf-8"):
    if line.lstrip().startswith("["): break
    m=re.match(r"^([A-Za-z0-9_.-]+)=([01])$", line.strip())
    if m: defaults.add(m.group(1))
assert set(keys) <= defaults, "native privacy schema contains non-top-level or non-boolean settings"
assert all(item["title"] and item["key"] for panel in panels for item in panel["items"])
print("PASS: generated 13 native VPN/privacy panels with",len(keys),"top-level boolean settings")
PY
python3 - "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" "$ROOT/scripts/native-vpn-config.sh" "$MODULE/scripts/native-vpn-config.sh" <<'PY'
import pathlib, re, sys
source_path, canonical_helper_path, module_helper_path = map(pathlib.Path, sys.argv[1:])
source = source_path.read_text(encoding="utf-8")
assert canonical_helper_path.is_file(), "canonical native VPN config writer missing"
assert module_helper_path.is_file(), "staged native VPN config writer missing from module"
assert canonical_helper_path.read_bytes() == module_helper_path.read_bytes(), "staged native VPN config writer differs from canonical source"
helper = canonical_helper_path.read_text(encoding="utf-8")
start = source.find("private void showNativeSettingsGroup(String panelId, String title)")
render = source.find("private void renderNativePrivacySettingsGroup", start)
edit_bridge = source.find("private void loadNativePrivacyEditEntries", render)
assert start >= 0 and render > start and edit_bridge > render, "native privacy method boundaries missing"
native_group = source[start:render]
native_render = source[render:edit_bridge]
for body in (native_group, native_render):
    for forbidden in ("webView.evaluateJavascript", "VPN_EDIT", "PGB.model.sw", "secVal(", "secSet(", "pgPersistNow("):
        assert forbidden not in body, "native privacy toggle path still depends on hidden WebView bridge: " + forbidden
for required in ("native-privacy-settings.json", "renderNativePrivacySettingsGroup", "setNativePrivacySetting"):
    assert required in native_group + native_render, "native privacy category missing native path: " + required

# The old WebView-based VPN_EDIT compatibility path was replaced by a real
# native editor. Keep it attached only to vpnPanel and assert the full native
# list -> choice/text editor -> validated Root writer path instead.
legacy = source[edit_bridge:source.find("private void setNativePrivacySetting", edit_bridge)]
assert 'if (!"vpnPanel".equals(panelId)) return;' in legacy, "advanced VPN editor must remain isolated to vpnPanel"
assert "showNativeVpnAdvancedEditor" in legacy, "VPN advanced editor entry is missing"

def method(signature):
    pos = source.find(signature)
    assert pos >= 0, "missing native VPN editor method: " + signature
    end = source.find("\n    private ", pos + len(signature))
    return source[pos:] if end < 0 else source[pos:end]

editor = method("private void showNativeVpnAdvancedEditor()")
item = method("private void showNativeVpnAdvancedItemDialog(String key, String currentValue)")
choice = method("private void showNativeVpnAdvancedChoice(String key, String currentValue,")
save = method("private void saveNativeVpnAdvancedValue(String key, String value)")
quote = method("private static String shellQuote(String value)")
assert "scripts/native-vpn-config.sh" in editor and 'list", 30000L' in editor, "native editor does not read the device [conf:vpn] helper"
assert "FXVPNCONF1" in editor and "availableKeys.add(key)" in editor, "native editor response parsing/listing is missing"
key_block = editor.split("String[] keys = {", 1)[1].split("};", 1)[0]
editor_keys = set(re.findall(r'"([a-z][a-z0-9_]*)"', key_block))
required_keys = {
    "local_ip", "local_port", "mixed_port", "remote_dns", "cn_dns", "test_url",
    "auto_update_h", "chnroute_url", "app_mode", "core_ver", "core_auto",
    "core_bin", "log_level", "hosts_cache_min", "pick_min_ms",
    "pick_test_timeout", "pick_max_nodes", "hide_level", "hide_mtu_clamp",
    "hide_udp_block_all", "hide_icmp_block_all", "hide_dot_block"
}
assert required_keys <= editor_keys, "native VPN editor dropped keys: " + ", ".join(sorted(required_keys - editor_keys))
assert "EditText input = new EditText(this)" in item and 'setPositiveButton("保存"' in item, "native text editor path is missing"
assert "showNativeVpnAdvancedChoice" in item and "saveNativeVpnAdvancedValue" in item, "native choice/save editor path is missing"
assert ".setSingleChoiceItems(" in choice and 'setPositiveButton("应用"' in choice, "native choice dialog is incomplete"
assert 'native-vpn-config.sh' in save and "shellQuote(key)" in save and "shellQuote(value)" in save, "native config write does not quote both arguments"
assert "String.valueOf(value)" in quote and ".replace(" in quote, "shell argument quoting is not present"

assert module_helper_path.is_file(), "shipped native-vpn-config.sh helper missing from module"
for required in ("FXVPNCONF1", "valid_key()", "validate_value()", "with_lock()", "mutate()", 'sh "$MP/scripts/apply.sh" fast', "[conf:vpn]", "VPN config rollback failed"):
    assert required in helper, "native VPN config helper missing safeguard: " + required
for key in required_keys:
    assert key in helper, "native VPN config helper does not handle editor key: " + key
print("PASS: VPN text/list/choice controls use the native editor and validated, locked, rollback-capable [conf:vpn] writer")

PY
HELPER="$MODULE/scripts/native-privacy-settings.sh"
[ -s "$HELPER" ] || fail "module-side native privacy writer missing"
sh -n "$HELPER" || fail "native privacy writer has shell syntax errors"
mkdir -p "$TMP/module/scripts" "$TMP/pg"
cp "$MODULE/scripts/util.sh" "$TMP/module/scripts/util.sh"
cp "$MODULE/scripts/default.conf" "$TMP/module/scripts/default.conf"
cp "$HELPER" "$TMP/module/scripts/native-privacy-settings.sh"
printf 'id=privacyguard\nversion=1.0.0\n' > "$TMP/module/module.prop"
cat > "$TMP/module/scripts/apply.sh" <<'APPLY'
#!/bin/sh
echo ran >> "$PG/apply-test.log"
[ "${FX_TEST_APPLY_FAIL:-0}" = 0 ]
APPLY
chmod 755 "$TMP/module/scripts/apply.sh"
cp "$MODULE/scripts/default.conf" "$TMP/pg/settings.conf"
printf '\nfx_native_test_keep=preserved\n' >> "$TMP/pg/settings.conf"
export MP="$TMP/module" PG="$TMP/pg"
key=$(awk -F= '/^\[/ {exit} $2 ~ /^[01]$/ {print $1; exit}' "$TMP/module/scripts/default.conf")
[ -n "$key" ] || fail "no top-level boolean key found in default.conf"
old=$(awk -F= -v key="$key" '$1==key {print $2; exit}' "$TMP/module/scripts/default.conf")
[ "$old" = 0 ] && new=1 || new=0
sh "$HELPER" list > "$TMP/list.out" || fail "native privacy flag listing failed"
grep -qx "$key=$old" "$TMP/list.out" || fail "native privacy list omitted the current boolean value"
if grep -q '^fx_native_test_keep=' "$TMP/list.out"; then
  fail "native privacy list exposed unrelated config data"
fi
if awk '!/^[A-Za-z0-9_.-]+=[01]$/ {bad=1} END {exit !bad}' "$TMP/list.out"; then
  fail "native privacy list exposed non-boolean or section data"
fi
sh "$HELPER" set "$key" "$new" >/dev/null || fail "native setting write/apply failed"
grep -qx "$key=$new" "$PG/settings.conf" || fail "native setting was not persisted"
sh "$HELPER" list > "$TMP/list-after.out" || fail "native privacy flag listing after write failed"
grep -qx "$key=$new" "$TMP/list-after.out" || fail "native privacy list did not reflect the saved value"
grep -qx "fx_native_test_keep=preserved" "$PG/settings.conf" || fail "unrelated config entry was not preserved"
[ -s "$PG/apply-test.log" ] || fail "module apply command was not invoked"
set +e
FX_TEST_APPLY_FAIL=1 sh "$HELPER" set "$key" "$old" >"$TMP/apply-failure.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 10 ] || fail "apply failure exit code should be 10, got $rc"
grep -qx "$key=$old" "$PG/settings.conf" || fail "persisted value was lost after apply failure"
grep -q 'saved=1 applied=0' "$TMP/apply-failure.out" || fail "apply failure was not distinguished from persistence"
set +e
sh "$HELPER" set not_a_real_fx_setting 1 >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "unknown setting key should be rejected"
: > "$PG/settings.conf.tmp.12345"
set +e
sh "$HELPER" set "$key" "$new" >"$TMP/busy.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "active pg_set temp transaction should return retryable exit 75, got $rc"
grep -qx "$key=$old" "$PG/settings.conf" || fail "busy transaction was overwritten"
rm -f "$PG/settings.conf.tmp.12345"
: > "$PG/settings.conf.txn.tmp"
set +e
sh "$HELPER" set "$key" "$new" >"$TMP/webui-busy.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "active WebUI transaction should return retryable exit 75, got $rc"
grep -qx "$key=$old" "$PG/settings.conf" || fail "WebUI transaction marker was overwritten"
echo "PASS: native privacy config persistence, allowlist, apply reporting and transaction guard"
