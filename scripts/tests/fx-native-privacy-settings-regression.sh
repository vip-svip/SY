#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE="${1:-$ROOT/fx-module}"
ASSETS="${TMPDIR:-/tmp}/fx-native-privacy-assets-$$"
TMP="${TMPDIR:-/tmp}/fx-native-privacy-test-$$"
fail(){ echo "FAIL: $*" >&2; exit 1; }
trap 'rm -rf "$ASSETS" "$TMP"' EXIT HUP INT TERM
[ -s "$MODULE/webroot/index.html" ] || fail "complete module WebUI source missing"
[ -s "$MODULE/scripts/default.conf" ] || fail "module default.conf missing"
python3 "$ROOT/fx-patches/patch_native_privacy_settings.py" "$MODULE" "$ASSETS"
python3 - "$ASSETS/native-privacy-settings.json" "$MODULE/scripts/default.conf" <<'PY'
import json, re, sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
expected={"vpnPanel","rootPanel","advPanel","netPanel","permPanel","sensorPanel","locationPanel","devicePanel","mediaPanel","filePanel","notifyPanel","kernelPanel","miscPanel"}
panels=data.get("panels",[])
assert data.get("schema_version")==1
assert {p["id"] for p in panels}==expected
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
python3 - "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java" <<'PY'
import pathlib, sys
source=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
start=source.find("private void showNativeSettingsGroup(String panelId, String title)")
render=source.find("private void renderNativePrivacySettingsGroup", start)
edit_bridge=source.find("private void loadNativePrivacyEditEntries", render)
assert start >= 0 and render > start and edit_bridge > render, "native privacy method boundaries missing"
native_group=source[start:render]
native_render=source[render:edit_bridge]
for body in (native_group, native_render):
    for forbidden in ("webView.evaluateJavascript", "VPN_EDIT", "PGB.model.sw", "secVal(", "secSet(", "pgPersistNow("):
        assert forbidden not in body, "native privacy toggle path still depends on hidden WebView bridge: "+forbidden
for required in ("native-privacy-settings.json", "renderNativePrivacySettingsGroup", "setNativePrivacySetting"):
    assert required in native_group + native_render, "native privacy category missing native path: "+required
# Non-boolean text/list/choice controls are retained as a clearly isolated
# compatibility path rather than silently disappearing during this migration.
legacy_end=source.find("private void setNativePrivacySetting", edit_bridge)
legacy=source[edit_bridge:legacy_end]
for required in ("webView.evaluateJavascript", "VPN_EDIT", "showNativeSettingsEditDialog"):
    assert required in legacy, "advanced non-boolean edit control was dropped: "+required
print("PASS: boolean privacy toggles use native config I/O; non-boolean editors remain available via isolated compatibility bridge")
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
: > "$PG/settings.conf.tmp"
set +e
sh "$HELPER" set "$key" "$new" >"$TMP/busy.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "active config transaction should return retryable exit 75, got $rc"
grep -qx "$key=$old" "$PG/settings.conf" || fail "busy transaction was overwritten"
echo "PASS: native privacy config persistence, allowlist, apply reporting and transaction guard"
