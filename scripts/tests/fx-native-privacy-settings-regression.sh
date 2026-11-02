#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE="\${1:-$ROOT/fx-module}"
ASSETS="\${TMPDIR:-/tmp}/fx-native-privacy-assets-$$"
TMP="\${TMPDIR:-/tmp}/fx-native-privacy-test-$$"
fail(){ echo "FAIL: $*" >&2; exit 1; }
trap 'rm -rf "$ASSETS" "$TMP"' EXIT HUP INT TERM
python3 "$ROOT/fx-patches/patch_native_privacy_settings.py" "$MODULE" "$ASSETS"
python3 - "$ASSETS/native-privacy-settings.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
expected={"rootPanel","advPanel","netPanel","permPanel","sensorPanel","locationPanel","devicePanel","mediaPanel","filePanel","notifyPanel","kernelPanel","miscPanel"}
panels=data.get("panels",[])
assert data.get("schema_version")==1
assert {p["id"] for p in panels}==expected
keys=[item["key"] for panel in panels for item in panel["items"]]
assert len(keys)>=90, len(keys)
assert len(keys)==len(set(keys)), "duplicate setting keys would make category ownership ambiguous"
assert all(item["title"] and item["key"] for panel in panels for item in panel["items"])
print("PASS: generated 12 native privacy panels with",len(keys),"unique settings")
PY
HELPER="$MODULE/scripts/native-privacy-settings.sh"
[ -s "$HELPER" ] || fail "module-side native privacy writer missing"
sh -n "$HELPER" || fail "native privacy writer has shell syntax errors"
mkdir -p "$TMP/module/scripts" "$TMP/pg"
cp "$MODULE/scripts/util.sh" "$TMP/module/scripts/util.sh"
cp "$MODULE/scripts/default.conf" "$TMP/module/scripts/default.conf"
cp "$HELPER" "$TMP/module/scripts/native-privacy-settings.sh"
: > "$TMP/module/module.prop"
cat > "$TMP/module/scripts/apply.sh" <<'APPLY'
#!/bin/sh
echo ran >> "$PG/apply-test.log"
[ "\${FX_TEST_APPLY_FAIL:-0}" = 0 ]
APPLY
chmod 755 "$TMP/module/scripts/apply.sh"
cp "$MODULE/scripts/default.conf" "$TMP/pg/settings.conf"
export MP="$TMP/module" PG="$TMP/pg"
sh "$HELPER" set cam_null 1 >/dev/null || fail "native setting write/apply failed"
grep -qx 'cam_null=1' "$PG/settings.conf" || fail "native setting was not persisted"
grep -qx 'vpn_mode=direct' "$PG/settings.conf" || fail "unrelated settings were not preserved"
[ -s "$PG/apply-test.log" ] || fail "module apply command was not invoked"
# An apply failure must report saved-but-not-applied, not pretend the write rolled back.
set +e
FX_TEST_APPLY_FAIL=1 sh "$HELPER" set cam_null 0 >"$TMP/apply-failure.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 10 ] || fail "apply failure exit code should be 10, got $rc"
grep -qx 'cam_null=0' "$PG/settings.conf" || fail "persisted value was lost after apply failure"
grep -q 'saved=1 applied=0' "$TMP/apply-failure.out" || fail "apply failure was not distinguished from persistence"
# A WebUI transaction marker must block native writes instead of racing its atomic commit.
: > "$PG/settings.conf.tmp"
set +e
sh "$HELPER" set cam_null 1 >"$TMP/busy.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 75 ] || fail "active config transaction should return retryable exit 75, got $rc"
grep -qx 'cam_null=0' "$PG/settings.conf" || fail "busy transaction was overwritten"
echo "PASS: native privacy config persistence, apply result, transaction guard, and rollback-safe reporting"
