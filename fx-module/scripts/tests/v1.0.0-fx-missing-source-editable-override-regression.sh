#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-missing-source-editable-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/mod/scripts" "$TMP/pg/cache" "$TMP/pg/fxrules-user"
cp "$ROOT/module.prop" "$TMP/mod/module.prop"
cp "$ROOT/scripts/util.sh" "$TMP/mod/scripts/util.sh"
cp "$ROOT/scripts/fileedit.sh" "$TMP/mod/scripts/fileedit.sh"
cat > "$TMP/pg/settings.conf" <<'CONF'
[list:fx]
fxfile://custom|User-created FX source|1
CONF
chmod 700 "$TMP/mod/scripts/fileedit.sh"
OUT=$(PG="$TMP/pg" CONF="$TMP/pg/settings.conf" sh "$TMP/mod/scripts/fileedit.sh" page fx:custom 1 60 65536)
printf '%s\n' "$OUT" | grep -Fq '"ok":1' || { printf '%s\n' "$OUT" >&2; echo 'FAIL: missing FX source should open as empty editable override' >&2; exit 1; }
printf '%s\n' "$OUT" | grep -Fq '"override":1' || { printf '%s\n' "$OUT" >&2; echo 'FAIL: editor should report user override' >&2; exit 1; }
[ -f "$TMP/pg/fxrules-user/custom.txt" ] || { echo 'FAIL: empty user override not created' >&2; exit 1; }
SZ=$(stat -c %a "$TMP/pg/fxrules-user/custom.txt" 2>/dev/null || stat -f %Lp "$TMP/pg/fxrules-user/custom.txt")
case "$SZ" in 600|400) ;; *) echo "FAIL: override has unsafe mode $SZ" >&2; exit 1 ;; esac
printf 'DOMAIN,example.test,REJECT\n' > "$TMP/insert.txt"
OUT=$(PG="$TMP/pg" CONF="$TMP/pg/settings.conf" sh "$TMP/mod/scripts/fileedit.sh" ins fx:custom 1 "$TMP/insert.txt")
printf '%s\n' "$OUT" | grep -Fq '"ok":1' || { printf '%s\n' "$OUT" >&2; echo 'FAIL: editor insert should write to user FX override' >&2; exit 1; }
grep -Fxq 'DOMAIN,example.test,REJECT' "$TMP/pg/fxrules-user/custom.txt" || { echo 'FAIL: rule was not persisted to override' >&2; exit 1; }
OUT=$(PG="$TMP/pg" CONF="$TMP/pg/settings.conf" MODDIR="$TMP/mod" sh -c '. "$MODDIR/scripts/util.sh"; pg_fx_expand')
printf '%s\n' "$OUT" | grep -Fq 'DOMAIN,example.test,REJECT' || { printf '%s\n' "$OUT" >&2; echo 'FAIL: runtime FX expansion did not consume user override' >&2; exit 1; }
echo 'FX missing source editable override integration regression: PASS'
