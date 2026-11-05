#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-native-script-store.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"
PG="$T/pg"
mkdir -p "$MOD/scripts/jsruntime" "$MOD/webroot" "$PG"
printf 'id=privacyguard\nversion=1.0.0\n' > "$MOD/module.prop"
cp "$ROOT/fx-patches/native-script-list.sh" "$MOD/scripts/jsruntime/native-list.sh"
chmod 755 "$MOD/scripts/jsruntime/native-list.sh"
if [ -s "$ROOT/fx-module/scripts/util.sh" ]; then
  cp "$ROOT/fx-module/scripts/util.sh" "$MOD/scripts/util.sh"
else
  # The targeted Host lane does not unpack the release module archive.
  # Supply only the pg_list contract used by this isolated store fixture.
  cat > "$MOD/scripts/util.sh" <<'UTIL'
pg_list() {
  [ "${1:-}" = script ] || return 1
  awk '
    $0=="[list:script]" {inside=1; next}
    /^\[/ {inside=0}
    inside {print}
  ' "$CONF"
}
UTIL
fi
cat > "$PG/settings.conf" <<'CONF'
mode=direct
keep_this=untouched
[list:script]
https://one.example/a.js|One|1
# comment row
[list:other]
keep|other|1
[list:script]
https://two.example/b.js|Two|0
[conf:vpn]
mode=global
CONF
export PG CONF="$PG/settings.conf"
SCRIPT="$MOD/scripts/jsruntime/native-list.sh"
sh -n "$SCRIPT" || fail "native script store shell syntax invalid"
list=$(sh "$SCRIPT" list)
printf '%s\n' "$list" | grep -q '^FXSCRIPT1$' || fail "list protocol header missing"
[ "$(printf '%s\n' "$list" | grep -c '|')" -eq 2 ] || fail "duplicate script sections were not merged"
value64=$(printf '%s' 'https://three.example/c.js' | base64 | tr -d '\n')
note64=$(printf '%s' 'Three' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$value64" "$note64" 1)" = "OK" ] || fail "add failed"
sh "$SCRIPT" list | grep -q "$(printf '%s' 'https://three.example/c.js' | base64 | tr -d '\n')" || fail "added row missing"
updated64=$(printf '%s' 'https://three.example/updated.js' | base64 | tr -d '\n')
updated_note64=$(printf '%s' 'Updated' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" update 3 "$updated64" "$updated_note64")" = "OK" ] || fail "update failed"
sh "$SCRIPT" list | grep -q "$(printf '%s' 'https://three.example/updated.js' | base64 | tr -d '\n')" || fail "updated value missing"
[ "$(sh "$SCRIPT" toggle 3 0)" = "OK" ] || fail "toggle failed"
sh "$SCRIPT" list | grep -q "$(printf '%s' 'https://three.example/updated.js' | base64 | tr -d '\n')|$(printf '%s' 'Updated' | base64 | tr -d '\n')|0" || fail "toggle state not persisted"
[ "$(sh "$SCRIPT" delete 2)" = "OK" ] || fail "delete failed"
[ "$(CONF="$PG/settings.conf" sh -c '. "$1/scripts/util.sh"; pg_list script | grep -v "^[[:space:]]*#" | grep -c .' sh "$MOD")" -eq 2 ] || fail "delete did not remove exactly one script"
grep -qx 'mode=direct' "$PG/settings.conf" || fail "global settings were lost"
grep -qx 'keep_this=untouched' "$PG/settings.conf" || fail "unrelated root setting was lost"
grep -Fqx 'keep|other|1' "$PG/settings.conf" || fail "other list section was lost"
grep -Fqx '[conf:vpn]' "$PG/settings.conf" || fail "conf section was lost"
before=$(sha256sum "$PG/settings.conf" | awk '{print $1}')
if sh "$SCRIPT" toggle 99 1 >/dev/null 2>&1; then fail "invalid index unexpectedly succeeded"; fi
after=$(sha256sum "$PG/settings.conf" | awk '{print $1}')
[ "$before" = "$after" ] || fail "invalid mutation changed settings.conf"
# Local JavaScript source must survive arbitrary pipes, line breaks and literal backslashes.
multiline=$(printf 'const value = "a|b";\nconst endpoint = "https://example.test";\nconst literal = "\\n";\nreturn value + literal;')
multi64=$(printf '%s' "$multiline" | base64 | tr -d '\n')
multi_note=$(printf '%s' 'Multiline source' | base64 | tr -d '\n')
add_result=$(sh "$SCRIPT" add "$multi64" "$multi_note" 1 2>&1) || fail "multiline local source add failed: $add_result"
[ "$add_result" = "OK" ] || fail "multiline local source add returned unexpected output: $add_result"
stored_row=$(sh "$SCRIPT" list | grep "|$multi_note|1$" | cut -d'|' -f1 | base64 -d)
case "$stored_row" in FXSRC_B64:*) stored=$(printf '%s' "${stored_row#FXSRC_B64:}" | base64 -d) ;; *) fail "local source was not stored in lossless base64 form" ;; esac
[ "$stored" = "$multiline" ] || fail "multiline local source round-trip corrupted content"
http64=$(printf '%s' 'http://insecure.example/script.js' | base64 | tr -d '\n')
if sh "$SCRIPT" add "$http64" "$multi_note" 1 >/dev/null 2>&1; then fail "insecure HTTP subscription unexpectedly accepted"; fi
# Remove product-level ceilings on individual sources, total entries and aggregate size.
large_source=$(awk 'BEGIN { for (i=0; i<70000; i++) printf "x" }')
large64=$(printf '%s' "$large_source" | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$large64" "$multi_note" 1)" = "OK" ] || fail "70 KiB local script was rejected"
[ "$(sh "$SCRIPT" list | grep -c '|')" -eq 4 ] || fail "large script was not retained"
i=1
while [ "$i" -le 8 ]; do
  [ "$(sh "$SCRIPT" add "$large64" "$multi_note" 1)" = "OK" ] || fail "large aggregate entry $i was rejected"
  i=$((i+1))
done
i=1
while [ "$i" -le 140 ]; do
  encoded=$(printf 'https://bulk.example/%s.js' "$i" | base64 | tr -d '\n')
  [ "$(sh "$SCRIPT" add "$encoded" "$note64" 1)" = "OK" ] || fail "script entry $i was rejected"
  i=$((i+1))
done
[ "$(sh "$SCRIPT" list | grep -c '|')" -eq 152 ] || fail "catalog truncated above 128 entries or former aggregate limit"
mkdir -p "$PG/jsruntime/staging"
staged="$PG/jsruntime/staging/fx-native-script-regression"
printf '%s' "$large_source" > "$staged"
[ "$(sh "$SCRIPT" add-file "$staged" "$multi_note" 1)" = "OK" ] || fail "file-backed large script import was rejected"
[ "$(sh "$SCRIPT" list | grep -c '|')" -eq 153 ] || fail "file-backed large script was not retained"
# The parser/serializer must decode FXSRC_B64 rows while keeping HTTPS URLs readable.
# The targeted Host lane has no release archive; use a minimal canonical parser fixture.
if [ -s "$ROOT/fx-module/webroot/index.html" ]; then
  cp "$ROOT/fx-module/webroot/index.html" "$MOD/webroot/index.html"
else
  cat > "$MOD/webroot/index.html" <<'HTML'
var v=(p[0]||'').replace(/\\n/g,'\n');
out.push(pgSan(e.v)+'|'+pgSan(e.note)+'|'+(e.on?1:0))
function pgParse(text){
HTML
fi
python3 "$ROOT/fx-patches/patch_native_script_store.py" "$MOD" >/dev/null
grep -Fq 'function pgDecodeScriptValue(s)' "$MOD/webroot/index.html" || fail "WebUI parser lacks local-source decoder"
grep -Fq "FXSRC_B64:'+pgB64(e.v)" "$MOD/webroot/index.html" || fail "WebUI serializer does not preserve local JS source"
before_patch=$(sha256sum "$MOD/webroot/index.html" | awk '{print $1}')
python3 "$ROOT/fx-patches/patch_native_script_store.py" "$MOD" >/dev/null
after_patch=$(sha256sum "$MOD/webroot/index.html" | awk '{print $1}')
[ "$before_patch" = "$after_patch" ] || fail "native script patcher is not idempotent"
[ -x "$MOD/scripts/jsruntime/local-run.sh" ] || fail "native QuickJS local runner was not installed"
cmp -s "$ROOT/fx-patches/native-script-run.sh" "$MOD/scripts/jsruntime/local-run.sh" || fail "installed local runner differs from canonical source"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
grep -Fq 'nativeScriptStoreCommand("add-file"' "$MAIN" || fail "Android script storage still transports source bytes in shell arguments"
grep -Fq 'storeNativeScriptFile(staged, displayName, "1"' "$MAIN" || fail "file imports do not use the file-backed store transport"
grep -Fq 'storeNativeScriptValue(value, name, enabled' "$MAIN" || fail "JSON imports do not use the file-backed store transport"
if grep -Fq 'total > 1024 * 1024' "$MAIN"; then fail "Android file import still has a 1 MiB cap"; fi
if grep -Fq 'MAX_NATIVE_SCRIPT_EXPORT_BYTES' "$MAIN"; then fail "Android script export still has a fixed payload cap"; fi
python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "add|add-file|update|toggle|delete)" in source, "file-backed action is not routed through the locked store"
start = source.index("      add-file)")
end = source.index("\n      update)", start)
branch = source[start:end]
assert 'first_line=$(sed -n \'1{p;q;}\' "$VALUE_FILE")' in branch, "file import must classify using a bounded first-line read"
assert 'base64 < "$VALUE_FILE" | tr -d \'\\n\' >> "$ROWS"' in branch, "local source must stream from the staged file into the config row"
assert 'value=$(cat "$VALUE_FILE")' not in branch, "local JS payload is still copied wholesale into a shell variable"
assert '/data/user/[0-9]*/de.privacyguard.adhook/cache/fx-native-script-*' in branch, "app-cache source path must match the exact FX package across Android users"
print("PASS: file-backed local source import stays streaming and accepts only FX app-cache staging paths")
PY

echo "PASS: native script-list backend supports CRUD, preserves unrelated config, round-trips multiline source and installs the local runner"
