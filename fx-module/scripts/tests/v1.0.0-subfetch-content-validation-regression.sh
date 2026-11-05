#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-content.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module" "$T/bin" "$T/state"
cp -a "$ROOT/." "$T/module/"
printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
cat > "$T/bin/curl.body" <<'CURL'
printf '%s\n' "$@" > "$TEST_CURL_ARGS"
out=''
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; esac
  shift
done
[ -n "$out" ] || exit 2
[ -s "$TEST_SUB_RESPONSE" ] || exit 3
if [ "$out" = "-" ]; then cat "$TEST_SUB_RESPONSE"; else cp "$TEST_SUB_RESPONSE" "$out"; fi
CURL
cat "$T/bin/curl.body" >> "$T/bin/curl"
rm -f "$T/bin/curl.body"
chmod 755 "$T/bin/curl"
export PATH="$T/bin:$PATH" TEST_SUB_RESPONSE="$T/response" TEST_CURL_ARGS="$T/curl.args"
url='https://sub.example.invalid/link?token=not-a-real-token'

# URL control whitespace must be rejected before cache-key generation or transport.
bad_url='https://sub.example.invalid/line
break'
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$bad_url" --force > "$T/bad-newline.out"
grep -Fq '"err":"invalid URL characters"' "$T/bad-newline.out"
bad_url=$(printf 'https://sub.example.invalid/tab\tpath')
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$bad_url" --force > "$T/bad-tab.out"
grep -Fq '"err":"invalid URL characters"' "$T/bad-tab.out"
bad_url=$(printf 'https://sub.example.invalid/cr\rpath')
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$bad_url" --force > "$T/bad-cr.out"
grep -Fq '"err":"invalid URL characters"' "$T/bad-cr.out"
key=$(printf '%s' "$url" | cksum | awk '{print $1}')
body="$T/state/subs/$key.txt"
meta="$T/state/subs/$key.meta"

# A 200 HTML/login page must not create a cache.
printf '<!doctype html><html><title>Login</title><body>verify you are human</body></html>\n' > "$T/response"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --force > "$T/html.out"
grep -Fq '"ok":0' "$T/html.out"
grep -Fq '网页/登录验证页' "$T/html.out"
[ ! -s "$body" ]

# A valid Clash YAML body is cached and metadata must never store the secret URL.
printf '\357\273\277proxies:\n  - {name: Tokyo, type: vless, server: edge.example.com, port: 443, uuid: 123e4567-e89b-12d3-a456-426614174000}\n' > "$T/response"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --force > "$T/valid.out"
grep -Fq '"ok":1' "$T/valid.out"
grep -Fq '"fetched":1' "$T/valid.out"
# Redirect policy must keep downloads on HTTP(S), and redirects HTTPS-only to prevent downgrade.
grep -Fxq -- "--proto" "$T/curl.args"
grep -Fxq -- "=http,https" "$T/curl.args"
grep -Fxq -- "--proto-redir" "$T/curl.args"
grep -Fxq -- "=https" "$T/curl.args"
cp "$body" "$T/body.before"
grep -Fq 'size=' "$meta"
if grep -Fq 'url=' "$meta"; then echo 'credential URL leaked into metadata' >&2; exit 1; fi

# A later 200 HTML response must fall back to the verified cache without replacing it.
printf '<html><body>Access denied - Cloudflare challenge</body></html>\n' > "$T/response"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --force > "$T/fallback.out"
grep -Fq '"ok":1' "$T/fallback.out"
grep -Fq '"fetched":0' "$T/fallback.out"
grep -Fq '"cached":1' "$T/fallback.out"
cmp -s "$T/body.before" "$body"
meta_mode=$(stat -c "%a" "$meta" 2>/dev/null) || { echo "cannot inspect subscription metadata permissions" >&2; exit 1; }
[ "$meta_mode" = 600 ] || { echo "subscription metadata permissions are $meta_mode, expected 600" >&2; exit 1; }
echo 'FX subscription response validation regression: PASS'
