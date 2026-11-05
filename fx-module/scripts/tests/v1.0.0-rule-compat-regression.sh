#!/system/bin/sh
# Regression coverage for the multi-ecosystem static rule importer.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
BASE_TMP=${TMPDIR:-/tmp}
TMP=$(mktemp -d "$BASE_TMP/fx-rule-compat-test.XXXXXX")
export TMPDIR="$TMP"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
cat > "$TMP/input.txt" <<'RULES'
! AdGuard Home / Adblock Plus / uBlock Origin list
||ads.example.com^
@@||safe.example.com^
||scoped.example.net^$third-party
example.org##.ad-banner
[Rule]
DOMAIN-SUFFIX,ads2.example.com,REJECT
DOMAIN-SUFFIX,allow.example.com,DIRECT
RULE-SET,https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/domains.txt,REJECT,no-resolve
host-suffix,quantum.example.com,reject
host-suffix,proxy.example.com,PROXY
DOMAIN-KEYWORD,tracker,REJECT
PROCESS-NAME,com.example.app,DIRECT
DEST-PORT,443,PROXY
NETWORK,tcp,REJECT
RULES
OUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/input.txt" 2>"$TMP/stderr")
ERR=$(cat "$TMP/stderr")
printf '%s\n' "$OUT" | grep -Fq '[list:domain]'
printf '%s\n' "$OUT" | grep -Fq 'safe.example.com|adblock-allow|1'
printf '%s\n' "$OUT" | grep -Fq 'allow.example.com|modconvert-whitelist|1'
printf '%s\n' "$OUT" | grep -Fq '[list:block]'
printf '%s\n' "$OUT" | grep -Fq 'ads.example.com|adblock-filter|1'
printf '%s\n' "$OUT" | grep -Fq 'quantum.example.com|modconvert|1'
printf '%s\n' "$OUT" | grep -Fq 'proxy.example.com,PROXY'
printf '%s\n' "$OUT" | grep -Fq 'DOMAIN-KEYWORD,tracker,REJECT'
printf '%s\n' "$OUT" | grep -Fq '[list:rule]'
printf '%s\n' "$OUT" | grep -Fq 'https://raw.githubusercontent.com/AdguardTeam/AdGuardSDNSFilter/master/Filters/domains.txt|modconvert-ruleset-reject|1'
# Third-party policy rules must remain in the generic route list, never in FX's
# dedicated anti-fraud/96110 ruleset.
FX_ROWS=$(printf '%s\n' "$OUT" | awk '/^\[list:fx\]$/ { in_fx=1; next } /^\[/ { in_fx=0 } in_fx && $0 !~ /^[[:space:]]*#/ && NF { print }')
[ -z "$FX_ROWS" ] || { echo "FAIL: third-party rules leaked into [list:fx]: $FX_ROWS" >&2; exit 1; }
RULE_ROWS=$(printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ { in_rule=1; next } /^\[/ { in_rule=0 } in_rule && $0 !~ /^[[:space:]]*#/ && NF { print }')
printf '%s\n' "$RULE_ROWS" | grep -Fq 'proxy.example.com,PROXY'
printf '%s\n' "$RULE_ROWS" | grep -Fq 'DOMAIN-KEYWORD,tracker,REJECT'
printf '%s\n' "$OUT" | grep -Fq 'PROCESS-NAME,com.example.app,DIRECT'
printf '%s\n' "$OUT" | grep -Fq 'DST-PORT,443,PROXY'
printf '%s\n' "$OUT" | grep -Fq 'NETWORK,tcp,REJECT'
printf '%s\n' "$ERR" | grep -Fq 'SKIP:adblock'
if printf '%s\n' "$OUT" | grep -Fq 'scoped.example.net|adblock-filter|1'; then
  echo 'FAIL: scoped Adblock option was widened into a global domain block' >&2
  exit 1
fi
if printf '%s\n' "$OUT" | grep -Fq 'example.org|adblock-filter|1'; then
  echo 'FAIL: cosmetic filter was misinterpreted as a network block' >&2
  exit 1
fi
cat > "$TMP/clash.yaml" <<'CLASH'
port: 7890
rules:
  - DOMAIN-SUFFIX, ads.clash.example, REJECT
  - DOMAIN-KEYWORD, tracker, REJECT
  - MATCH, PROXY
proxy-groups:
  - name: Proxy
    type: select
    proxies: [DIRECT]
CLASH
COUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/clash.yaml" 2>"$TMP/clash.stderr")
printf '%s\n' "$COUT" | grep -Fq 'ads.clash.example|modconvert|1'
printf '%s\n' "$COUT" | grep -Fq 'DOMAIN-KEYWORD,tracker,REJECT'
printf '%s\n' "$COUT" | grep -Fq 'MATCH,PROXY'
if printf '%s\n' "$COUT" | grep -Fq 'Proxy|modconvert|1'; then
  echo 'FAIL: Clash proxy-group metadata was treated as a filtering rule' >&2
  exit 1
fi
cat > "$TMP/script.conf" <<'SCRIPT'
[Script]
Rewrite = type=http-response,pattern=^https://example\.com/api/.*,script-path=https://scripts.example.net/rewrite.js
SCRIPT
SOUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/script.conf" 2>"$TMP/script.stderr")
printf '%s\n' "$SOUT" | grep -Fq '[list:script]'
printf '%s\n' "$SOUT" | grep -Fq 'https://scripts.example.net/rewrite.js|FXMETA_B64:'
META=$(printf '%s\n' "$SOUT" | awk -F'|' '/scripts.example.net\/rewrite.js/ {print $2; exit}' | sed 's/^FXMETA_B64://')
printf '%s' "$META" | base64 -d | grep -q '^response'
printf '%s' "$META" | base64 -d | grep -Fq '^https://example'
grep -Fq 'base64 -d' "$ROOT/scripts/jsruntime/sync-subs.sh"
printf '%s\n' 'PASS: static ecosystem import, supported script declarations, Clash/Mihomo YAML rules subset, whitelist precedence, conservative skips'
