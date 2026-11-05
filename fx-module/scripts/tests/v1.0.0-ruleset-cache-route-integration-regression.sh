#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-ruleset-route.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
URL='https://rules.example.test/domains.txt'
mkdir -p "$T/cache/rules"
cat > "$T/rules.module" <<'MODULE'
#!name=Remote text rule set
[Rule]
RULE-SET,https://rules.example.test/domains.txt,REJECT,no-resolve
MODULE
TMPDIR="$T" sh "$ROOT/scripts/modconvert.sh" --emit "$T/rules.module" > "$T/settings.conf"
KEY=$(printf '%s' "$URL" | cksum | awk '{print $1}')
printf '%s\n' 'blocked.example.test' '||adblock.example.test^' '0.0.0.0 host.example.test' > "$T/cache/rules/$KEY"
sha256sum "$T/cache/rules/$KEY" | awk '{print $1}' > "$T/cache/rules/$KEY.sha256"
PG="$T" VPNRULE_WORK="$T/work" sh "$ROOT/scripts/vpnrule.sh" --json > "$T/compiled.json"
grep -Fq '"domain_suffix":["blocked.example.test"]' "$T/compiled.json"
grep -Fq '"domain_suffix":["adblock.example.test"]' "$T/compiled.json"
grep -Fq '"domain_suffix":["host.example.test"]' "$T/compiled.json"
grep -Fq '"compiled":3' "$T/compiled.json"
if grep -Fq '"skipped":1' "$T/compiled.json"; then
  echo 'FAIL: remote text RULE-SET was not consumed by route compiler' >&2
  exit 1
fi
echo 'PASS: remote text RULE-SET cache reaches route compiler as active reject routes'
