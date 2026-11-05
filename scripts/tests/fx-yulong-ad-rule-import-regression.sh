#!/system/bin/sh
set -eu
BASE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
if [ -d "$BASE_ROOT/fx-module" ]; then
  MODULE=${1:-"$BASE_ROOT/fx-module"}
elif [ -z "${1:-}" ]; then
  # The normal Host checkout intentionally excludes the Release-restored
  # fx-module tree and its 200k+ upstream rule payload. Do not pretend the
  # complete dataset was tested here; validate the importer contract and leave
  # full rule-count/DNS pipeline assertions to the KernelSU package lane.
  python3 - "$BASE_ROOT/scripts/integrate_yulong_ad_rules.py" "$BASE_ROOT/scripts/decode_yulong_ad_tries.py" "$0" <<'PY'
from pathlib import Path
import sys
integrator, decoder, regression = [Path(x).read_text(encoding="utf-8") for x in sys.argv[1:]]
required_integrator = (
    "rulefiles/Yulong_AdBlock.txt",
    "rulefiles/Yulong_AdBlock_Cosmetic.txt",
    "rulefiles/Yulong_AdBlock_Review.jsonl",
    "if rules.stat().st_size < 1_000_000:",
    "builtin://Yulong_AdBlock.txt",
    'if [ -n "$_yulong_file" ]; then',
    'config.split("[list:fx]", 1)',
)
for token in required_integrator:
    assert token in integrator, f"Yulong importer contract missing: {token}"
assert "def main()" in decoder and "cosmetic_output" in decoder, "TRIE decoder must emit the separate cosmetic stream"
assert "domains=210118" in regression or "len(domains)==210118" in regression, "pinned DNS-safe domain baseline missing"
assert "len(selectors)==3476" in regression, "cosmetic/exception preservation baseline missing"
assert "len(set(domains))==len(domains)" in regression, "duplicate DNS terminal check missing"
assert 'sh scripts/tests/fx-yulong-ad-rule-import-regression.sh fx-module' in Path(".github/workflows/build-fx-kernelsu.yml").read_text(encoding="utf-8"), "full module regression is not wired into KernelSU package lane"
print("PASS: Yulong importer static Host contract; full Release dataset validation is deferred to KernelSU package lane.")
PY
  exit 0
else
  MODULE=$1
fi
RULE="$MODULE/rulefiles/Yulong_AdBlock.txt"
COSMETIC="$MODULE/rulefiles/Yulong_AdBlock_Cosmetic.txt"
CONF="$MODULE/scripts/default.conf"
UTIL="$MODULE/scripts/util.sh"
AGH="$MODULE/scripts/adguardhome.sh"
# The decoded Yulong rule payload is generated from the checksum-pinned APK
# only in the KernelSU packaging lane. Host-only source checkouts intentionally
# omit those generated files; an explicitly supplied module path is strict.
if [ ! -s "$RULE" ] || [ ! -s "$COSMETIC" ]; then
  if [ -z "${1:-}" ]; then
    echo "SKIP: generated Yulong DNS/Cosmetic rule payload is absent in the Host-only source checkout; the KernelSU package lane supplies the restored module explicitly."
    exit 0
  fi
  echo "FAIL: explicitly supplied module is missing decoded Yulong DNS/Cosmetic rule payload." >&2
  exit 1
fi
[ -s "$CONF" ] && [ -s "$UTIL" ] && [ -s "$AGH" ]
python3 - "$RULE" "$COSMETIC" <<'PY'
import pathlib,re,sys
rules=pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
cos=pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
domains=[x for x in rules if x and not x.startswith("#")]
selectors=[x for x in cos if x and not x.startswith("!")]
pat=re.compile(r"^[0-9a-fA-F:.]+[ \t]+[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$")
assert len(domains)==210118, f"expected 210118 unique DNS domains, got {len(domains)}"
assert len(set(domains))==len(domains), "decoded DNS domain list contains duplicates"
assert len(selectors)==3476, f"expected 3476 preserved cosmetic/exception rules, got {len(selectors)}"
assert all(pat.fullmatch(x) for x in domains), "non-DNS-safe terminal entered Hosts list"
assert any("##" in x for x in selectors) and any("#@#" in x for x in selectors)
assert "GPL-3.0" in rules[:10][0] or any("GPL-3.0" in x for x in rules[:10]), "license attribution missing"
PY
grep -Fq 'builtin://Yulong_AdBlock.txt|' "$CONF"
grep -Fq "_mg_yulong_entry='builtin://Yulong_AdBlock.txt|" "$UTIL"
grep -Fq '_yulong_enabled=$(awk -F'"'"'|'"'"'' "$AGH"
grep -Fq 'if [ -n "$_yulong_file" ]; then' "$AGH"
awk '
  /^\[list:fx\][[:space:]]*$/ {section="fx"; next}
  /^\[/ {section=""}
  section=="fx" && /Yulong_AdBlock/ {bad=1}
  END {exit bad}
' "$CONF" || { echo 'FAIL: Yulong ad domains leaked into FX anti-fraud rules' >&2; exit 1; }

T="${TMPDIR:-/tmp}/fx-yulong-ad-dns-$$"
mkdir -p "$T/mod/scripts" "$T/mod/fxrules" "$T/mod/rulefiles" "$T/pg"
trap 'rm -rf "$T"' EXIT HUP INT TERM
cp "$AGH" "$T/mod/scripts/adguardhome.sh"
printf 'DOMAIN,anti-fraud.example,REJECT\n' > "$T/mod/fxrules/anti_fraud_96110.txt"
printf '0.0.0.0 ads.example\n0.0.0.0 tracker.example\n# ignored\n' > "$T/mod/rulefiles/Yulong_AdBlock.txt"
printf '[list:rule]\nbuiltin://Yulong_AdBlock.txt|Yulong|1\n' > "$T/pg/settings.conf"
sh "$T/mod/scripts/adguardhome.sh" render-config "$T/mod" "$T/pg" > "$T/enabled.yaml"
grep -Fq '||anti-fraud.example^' "$T/enabled.yaml"
grep -Fq '||ads.example^' "$T/enabled.yaml"
grep -Fq '||tracker.example^' "$T/enabled.yaml"
printf '[list:rule]\nbuiltin://Yulong_AdBlock.txt|Yulong|0\n' > "$T/pg/settings.conf"
sh "$T/mod/scripts/adguardhome.sh" render-config "$T/mod" "$T/pg" > "$T/disabled.yaml"
grep -Fq '||anti-fraud.example^' "$T/disabled.yaml"
! grep -Fq '||ads.example^' "$T/disabled.yaml"

cp "$RULE" "$T/mod/rulefiles/Yulong_AdBlock.txt"
printf '[list:rule]\nbuiltin://Yulong_AdBlock.txt|Yulong|1\n' > "$T/pg/settings.conf"
sh "$T/mod/scripts/adguardhome.sh" render-config "$T/mod" "$T/pg" > "$T/large.yaml"
grep -Fq '||0.avmarket.rs^' "$T/large.yaml"
[ "$(grep -c '^  - ' "$T/large.yaml" | tr -d ' ')" -gt 200000 ]
! grep -Eq '##|#@#|<script|scriptlet' "$T/large.yaml"

mkdir -p "$T/mod/scripts" "$T/mod/rulefiles" "$T/work" "$T/pg2"
cp "$MODULE/scripts/vpnrule.sh" "$T/mod/scripts/vpnrule.sh"
cp "$UTIL" "$T/mod/scripts/util.sh"
printf '0.0.0.0 ads.example\n0.0.0.0 tracker.example\n' > "$T/mod/rulefiles/Yulong_AdBlock.txt"
cat > "$T/settings.conf" <<'__RULE_CONF__'
fx=1
[list:rule]
builtin://Yulong_AdBlock.txt|Yulong|1
[list:fx]
__RULE_CONF__
PG="$T/pg2" CONF="$T/settings.conf" MODDIR="$T/mod" VPNRULE_SRC="$T/settings.conf" VPNRULE_WORK="$T/work" \
  sh "$T/mod/scripts/vpnrule.sh" --emit > "$T/routes.json"
grep -Fq '"domain_suffix":["ads.example"]' "$T/routes.json"
grep -Fq '"domain_suffix":["tracker.example"]' "$T/routes.json"
! grep -Eq '##|#@#|scriptlet' "$T/routes.json"
sh -n "$AGH"
sh -n "$UTIL"
echo 'PASS: Yulong 7.0.1 TRIE data imported, DNS/Hosts+AdGuard+sing-box paths tested, UI toggle state honored, anti-fraud namespace isolated'
