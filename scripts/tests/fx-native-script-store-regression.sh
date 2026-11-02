#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fail(){ echo "FAIL: $*" >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-native-script-store.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"
PG="$T/pg"
mkdir -p "$MOD/scripts/jsruntime" "$PG"
printf 'id=privacyguard\nversion=1.0.0\n' > "$MOD/module.prop"
cp "$ROOT/fx-patches/native-script-list.sh" "$MOD/scripts/jsruntime/native-list.sh"
chmod 755 "$MOD/scripts/jsruntime/native-list.sh"
cp "$ROOT/fx-module/scripts/util.sh" "$MOD/scripts/util.sh"
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
nonhttps64=$(printf '%s' 'javascript:alert(1)' | base64 | tr -d '\\n')
if sh "$SCRIPT" add "$nonhttps64" "$note64" 1 >/dev/null 2>&1; then fail "non-HTTPS script unexpectedly accepted"; fi
before=$(sha256sum "$PG/settings.conf" | awk '{print $1}')
if sh "$SCRIPT" toggle 99 1 >/dev/null 2>&1; then fail "invalid index unexpectedly succeeded"; fi
after=$(sha256sum "$PG/settings.conf" | awk '{print $1}')
[ "$before" = "$after" ] || fail "invalid mutation changed settings.conf"
# Script source values retain line breaks and literal backslash-n sequences in settings.conf.
multiline=$(printf 'line one\nline two\\n literal|pipe')
multi64=$(printf '%s' "$multiline" | base64 | tr -d '\n')
multi_note=$(printf '%s' 'Multiline source' | base64 | tr -d '\n')
[ "$(sh "$SCRIPT" add "$multi64" "$multi_note" 1)" = "OK" ] || fail "multiline script add failed"
stored=$(sh "$SCRIPT" list | sed -n '4p' | cut -d'|' -f1 | base64 -d)
expected=$(printf 'line one\\nline two\\\\n literal｜pipe')
[ "$stored" = "$expected" ] || fail "multiline script escaping corrupted source"
# Both the parser and serializer must understand the script-specific escape format.
grep -Fq 'function pgUnescapeScript(s)' "$ROOT/fx-module/webroot/index.html" || fail "WebUI parser lacks multiline script decoder"
grep -Fq 'pgEscapeScript(e.v)' "$ROOT/fx-module/webroot/index.html" || fail "WebUI serializer does not preserve multiline script values"
before_patch=$(sha256sum "$ROOT/fx-module/webroot/index.html" | awk '{print $1}')
python3 "$ROOT/fx-patches/patch_native_script_store.py" "$ROOT/fx-module" >/dev/null
after_patch=$(sha256sum "$ROOT/fx-module/webroot/index.html" | awk '{print $1}')
[ "$before_patch" = "$after_patch" ] || fail "native script patcher is not idempotent"
echo "PASS: native script-list backend supports CRUD, preserves unrelated config and round-trips multiline script values"
