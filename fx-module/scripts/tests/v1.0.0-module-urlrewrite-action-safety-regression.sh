#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-urlrewrite-actions.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
cat > "$TMP/actions.module" <<'MODULE'
[URL Rewrite]
^https?:\\/\\/app\\.bilibili\\.com\\/x\\/resource\\/ip - reject
^https://app.bilibili.com/x/v2/splash/show - reject-dict
^https://manga.bilibili.com/twirp/comic - reject-array
(^https://app.bilibili.com/api/.*)([?&]foo=1)(.*) - 302$1$3
^https://api.bilibili.com/x/.* - reject-200
^https://app.bilibili.com/x/compact-reject
(^https://app.bilibili.com/api/.*)([?&]foo=1)(.*)-302$1$3
MODULE
OUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/actions.module" 2>"$TMP/err")
if printf '%s\n' "$OUT" | grep -E 'DOMAIN,(app|manga|api)\.bilibili\.com,REJECT'; then
  echo 'FAIL: URL Rewrite was widened to domain-wide blocking' >&2; exit 1
fi
printf '%s\n' "$OUT" | grep -Fq '[list:urlrewrite]' || { echo 'FAIL: URL Rewrite runtime section missing' >&2; exit 1; }
[ "$(printf '%s\n' "$OUT" | grep -c 'FXURLREWRITE_B64')" -eq 7 ] || { echo 'FAIL: expected all five URL Rewrite actions to be preserved' >&2; exit 1; }
for action in reject reject-dict reject-array 302 reject-200; do
  printf '%s\n' "$OUT" | grep -Fq '[list:urlrewrite]' || { echo "FAIL: URL Rewrite section missing for $action" >&2; exit 1; }
done
printf '%s\n' 'PASS: reject/reject-dict/reject-array/reject-200/302 URL rewrites are preserved for runtime and not widened to domain blocks'
