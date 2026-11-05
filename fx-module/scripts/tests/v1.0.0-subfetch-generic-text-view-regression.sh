#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subview.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module" "$T/bin" "$T/state"
cp -a "$ROOT/." "$T/module/"
printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
cat >> "$T/bin/curl" <<'CURL'
out=''
while [ "$#" -gt 0 ]; do case "$1" in -o) shift; out=$1 ;; esac; shift; done
[ "$out" = '-' ] || [ -n "$out" ] || exit 2
if [ "$out" = '-' ]; then cat "$TEST_SUB_RESPONSE"; else cp "$TEST_SUB_RESPONSE" "$out"; fi
CURL
chmod 755 "$T/bin/curl"
export PATH="$T/bin:$PATH" TEST_SUB_RESPONSE="$T/response"
url='https://example.invalid/module/aloha.module'
key=$(printf '%s' "$url" | cksum | awk '{print $1}')
printf '#!name=Example module\n[Script]\nrequest = type=http-response,pattern=https://api.example.invalid,script-path=https://example.invalid/a.js\n[MITM]\nhostname = api.example.invalid\n' > "$T/response"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --view > "$T/view.out"
grep -Fq '"ok":1' "$T/view.out"
grep -Fq '"fetched":1' "$T/view.out"
# Explicit refresh must bypass a valid generic-text cache and atomically update it.
printf '#!name=Updated module\n[Rule]\nDOMAIN,ads.example.com,REJECT\n' > "$T/response"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --view-force > "$T/view-force.out"
grep -Fq '"fetched":1' "$T/view-force.out"
grep -Fq 'Updated module' "$T/state/subs/$key.txt"
# The same generic body must not be accepted as a VPN-node subscription.
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" "$url" --force > "$T/strict.out"
grep -Fq '"ok":0' "$T/strict.out"
# HTML challenge pages are never accepted even in generic view mode.
printf '<!doctype html><html><body>verify you are human</body></html>\n' > "$T/response"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" 'https://example.invalid/challenge' --view > "$T/html.out"
grep -Fq '"ok":0' "$T/html.out"
echo 'FX generic script/rule text view regression: PASS'
