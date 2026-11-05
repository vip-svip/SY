#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-module-scope-test.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
cat > "$TMP/bili.module" <<'MODULE'
#!name=哔哩哔哩去广告
[MITM]
hostname = %APPEND% app.bilibili.com, api.live.bilibili.com, api.vc.bilibili.com, api.bilibili.com
[URL Rewrite]
^https?:\\/\\/app\\.bilibili\\.com\\/x\\/resource\\/ip - reject
^https://app.bilibili.com/x/v2/splash/show - reject-dict
^https?:\\/\\/manga\\.bilibili\\.com\\/twirp\\/comic\\.v1\\.Comic\\/(Flash|ListFlash) - reject-dict
[Script]
bili1=type=http-response,pattern=^https?:\\/\\/app\\.bilibili\\.com\\/x\\/v2\\/feed\\/index,requires-body=1,script-path=https://raw.githubusercontent.com/example/bili.js
bili2=type=http-response,pattern=^https?:\\/\\/app\\.bilibili\\.com\\/x\\/v2\\/account\\/mine,requires-body=1,script-path=https://raw.githubusercontent.com/example/bili.js
bili3=type=http-response,pattern=^https?:\\/\\/api\\.live\\.bilibili\\.com\\/xlive,requires-body=1,script-path=https://raw.githubusercontent.com/example/bili.js
MODULE
OUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/bili.module" 2>"$TMP/err")
# Path-scoped rewrite must never be broadened to a domain-wide block.
if printf '%s\n' "$OUT" | grep -E 'DOMAIN,app\.bilibili\.com,REJECT|DOMAIN,manga\.bilibili\.com,REJECT'; then
  echo 'FAIL: URL Rewrite path was widened into a domain block' >&2; exit 1
fi
printf '%s\n' "$OUT" | grep -Fq '[list:urlrewrite]' || { echo 'FAIL: URL Rewrite runtime section missing' >&2; exit 1; }
# Same script URL with different request/response match patterns must remain separate.
[ "$(printf '%s\n' "$OUT" | grep -c 'https://raw.githubusercontent.com/example/bili.js|FXMETA_B64:')" -eq 3 ] || { echo 'FAIL: same script URL entries with different metadata were deduplicated' >&2; exit 1; }
META_COUNT=$(printf '%s\n' "$OUT" | grep 'https://raw.githubusercontent.com/example/bili.js|FXMETA_B64:' | cut -d'|' -f2 | sed 's/^FXMETA_B64://' | while IFS= read -r m; do printf '%s' "$m" | base64 -d; done | grep -c '^response$')
[ "$META_COUNT" -eq 3 ] || { echo 'FAIL: not all script trigger metadata survived' >&2; exit 1; }
# Aloha-style module headers (including CRLF-compatible metadata), requires-body,
# and a plain URL pattern are accepted; regex commas before script-path survive.
cat > "$TMP/aloha.module" <<'ALOHA'
#!url=https://yfamilys.com/module/aloha.module
#!name=AlohaVPN浏览器
#!desc=AlohaVPN浏览器
[Script]
AlohaVPN浏览器=type=http-response,pattern=https://api.alohaprofile.com/v1/profile_info,requires-body=1,script-path=https://raw.githubusercontent.com/Marol62926/MarScrpt/main/aloha.js
CommaRegex=type=http-response,pattern=^https://api.example.test/(foo,bar)$,requires-body=1,script-path=https://raw.githubusercontent.com/example/aloha-comma.js
[MITM]
hostname= %APPEND% api.alohaprofile.com
ALOHA
AOUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/aloha.module" 2>"$TMP/aloha.err")
printf '%s\n' "$AOUT" | grep -Fq 'https://raw.githubusercontent.com/Marol62926/MarScrpt/main/aloha.js|FXMETA_B64:' || { echo 'FAIL: Aloha requires-body response script not imported' >&2; exit 1; }
AMETA=$(printf '%s\n' "$AOUT" | awk -F'|' '/Marol62926\/MarScrpt\/main\/aloha.js/ {print $2; exit}' | sed 's/^FXMETA_B64://')
printf '%s' "$AMETA" | base64 -d | grep -Fxq 'response' && printf '%s' "$AMETA" | base64 -d | grep -Fxq 'https://api.alohaprofile.com/v1/profile_info' || { echo 'FAIL: Aloha response URL match metadata lost or polluted by requires-body' >&2; exit 1; }
CMETA=$(printf '%s\n' "$AOUT" | awk -F'|' '/aloha-comma.js/ {print $2; exit}' | sed 's/^FXMETA_B64://')
printf '%s' "$CMETA" | base64 -d | grep -Fxq '^https://api.example.test/(foo,bar)$' || { echo 'FAIL: comma inside regex pattern was truncated or metadata field leaked into pattern' >&2; exit 1; }
printf '%s\n' "$AOUT" | grep -Fq '[list:mitmhost]' || { echo 'FAIL: MITM hostname allowlist section missing' >&2; exit 1; }
printf '%s\n' "$AOUT" | grep -Fq 'api.alohaprofile.com|modconvert-mitmhost|1' || { echo 'FAIL: Aloha MITM hostname was not connected to runtime allowlist' >&2; exit 1; }
printf '%s\n' 'PASS: URL Rewrite entries preserved; repeated triggers retained; Aloha module and comma regex imported' 
