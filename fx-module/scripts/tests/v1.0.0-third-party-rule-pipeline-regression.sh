#!/bin/sh
# End-to-end source contract: converter output reaches route compiler and does not leak into FX.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-thirdparty-pipeline.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM HUP
cat > "$TMP/sample.module" <<'MODULE'
#!name=Routing test
[Rule]
DOMAIN-SUFFIX,proxy.example.test,PROXY,no-resolve
DOMAIN-SUFFIX,blocked.example.test,REJECT,no-resolve
DOMAIN-KEYWORD,tracker,REJECT,no-resolve
RULE-SET,https://rules.example.test/domains.txt,REJECT,no-resolve
||adblock.example.test^
MODULE
OUT=$(TMPDIR="$TMP" sh "$ROOT/scripts/modconvert.sh" --emit "$TMP/sample.module" 2>"$TMP/err")
printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ { on=1; next } /^\[/ { on=0 } on && /proxy.example.test,PROXY/ { found=1 } END { exit !found }'
printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ { on=1; next } /^\[/ { on=0 } on && /DOMAIN-KEYWORD,tracker,REJECT/ { found=1 } END { exit !found }'
printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ { on=1; next } /^\[/ { on=0 } on && /rules.example.test\/domains.txt/ { found=1 } END { exit !found }'
printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ { on=1; next } /^\[/ { on=0 } on && /DOMAIN-SUFFIX,blocked.example.test,REJECT/ { found=1 } END { exit !found }'
printf '%s\n' "$OUT" | awk '/^\[list:rule\]$/ { on=1; next } /^\[/ { on=0 } on && /DOMAIN-SUFFIX,adblock.example.test,REJECT/ { found=1 } END { exit !found }'
if printf '%s\n' "$OUT" | awk '/^\[list:fx\]$/ { on=1; next } /^\[/ { on=0 } on && $0 !~ /^[[:space:]]*#/ && NF { found=1 } END { exit !found }'; then
  echo 'FAIL: third-party rules contaminated FX-specific rule list' >&2; exit 1
fi
# Route rule lines must not be copied verbatim into the generated system hosts file.
grep -Fq '_entry_type=$(printf' "$ROOT/scripts/apply.sh"
grep -Fq 'DOMAIN-KEYWORD|DOMAIN-REGEX' "$ROOT/scripts/apply.sh"
grep -Fq 'extract_rules "$SRC"' "$ROOT/scripts/vpnrule.sh"
# Check the actual WebUI import path invokes conversion for uploaded and pasted modules,
# merges converted list sections and persists before claiming success.
grep -Fq 'function pgConvertThirdPartyModule' "$ROOT/webroot/index.html"
grep -Fq 'pgConvertThirdPartyModule(txt,f.name)' "$ROOT/webroot/index.html"
grep -Fq "pgConvertThirdPartyModule(content,'pasted.module')" "$ROOT/webroot/index.html"
grep -Fq 'pgPersistNow().then(function(ok)' "$ROOT/webroot/index.html"
echo 'FX third-party module import → separate route list → compiler/runtime pipeline: PASS'

# Avoid mutating the model while another config write is pending.
grep -Fq 'function pgWaitForPersistIdle(tries)' "$ROOT/webroot/index.html"
grep -Fq 'return pgWaitForPersistIdle(0).then(function()' "$ROOT/webroot/index.html"

# Temp modules are atomically allocated by privileged mktemp, not predictable JS timestamps/random.
grep -Fq 'mktemp /data/local/tmp/fxmod.XXXXXXXXXX' "$ROOT/webroot/index.html"
! grep -Fq "String(Date.now())+'_'+String(Math.floor(Math.random()*1000000))" "$ROOT/webroot/index.html"
