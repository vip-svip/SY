#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-urlrewrite-bridge.$$
mkdir -p "$TMP/pg/mitm" "$TMP/worktmp"
(cd "$ROOT/mitm" && go build -o "$TMP/pg-mitm-validator" .)
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
cat > "$TMP/module.sgmodule" <<'MODULE'
[URL Rewrite]
^https://app\.bilibili\.com/x/resource/ip - reject
(^https://app\.bilibili\.com/api/.*)([?&]foo=1)(.*) - 302$1$3
^https://manga\.bilibili\.com/twirp/comic - reject-array
^https://app\.bilibili\.com/x/compact-reject
(^https://app\.bilibili\.com/api/.*)([?&]bar=1)(.*)-302$1$3
MODULE
OUT=$(TMPDIR="$TMP/worktmp" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/module.sgmodule" 2>"$TMP/err")
printf '%s\n' "$OUT" | grep -Fq '[list:urlrewrite]'
printf '%s\n' "$OUT" | grep -E 'DOMAIN,(app|manga)\.bilibili\.com,REJECT' && { echo 'FAIL: rewrite widened to domain block' >&2; exit 1; }
printf '%s\n' "$OUT" > "$TMP/pg/settings.conf"
PG="$TMP/pg" FX_SETTINGS="$TMP/pg/settings.conf" FX_MODDIR="$ROOT" FX_MITM_BIN="$TMP/pg-mitm-validator" sh "$ROOT/scripts/sync-urlrewrite.sh"
[ "$(wc -l < "$TMP/pg/mitm/url-rewrite.conf" | tr -d ' ')" = 5 ] || { echo 'FAIL: runtime manifest does not contain all imported rules' >&2; cat "$TMP/pg/mitm/url-rewrite.conf" >&2; exit 1; }
grep -Fq ' - reject' "$TMP/pg/mitm/url-rewrite.conf"
grep -Fq ' - 302$1$3' "$TMP/pg/mitm/url-rewrite.conf"
grep -Fq ' - reject-array' "$TMP/pg/mitm/url-rewrite.conf"
grep -Eq ' - reject$' "$TMP/pg/mitm/url-rewrite.conf"
grep -Fq ' - 302$1$3' "$TMP/pg/mitm/url-rewrite.conf"
# A malformed regex must be rejected before atomic publication; keep old bytes.
cp "$TMP/pg/mitm/url-rewrite.conf" "$TMP/known-good.conf"
printf '%s\n' '[list:urlrewrite]' 'W2gtLSAtIHJlamVjdA==|FXURLREWRITE_B64|1' > "$TMP/pg/settings.conf"
if PG="$TMP/pg" FX_SETTINGS="$TMP/pg/settings.conf" FX_MODDIR="$ROOT" FX_MITM_BIN="$TMP/pg-mitm-validator" sh "$ROOT/scripts/sync-urlrewrite.sh" >/dev/null 2>&1; then
  echo 'FAIL: invalid regex manifest unexpectedly published' >&2; exit 1
fi
cmp -s "$TMP/known-good.conf" "$TMP/pg/mitm/url-rewrite.conf" || { echo 'FAIL: failed validation changed active manifest' >&2; exit 1; }
printf '%s\n' 'PASS: URL Rewrite module entries round-trip into the runtime manifest without domain widening'
