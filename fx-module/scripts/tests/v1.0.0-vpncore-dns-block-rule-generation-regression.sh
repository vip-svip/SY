#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vpn-dns-block.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/cache"
cat > "$T/settings.conf" <<'CONF'
[list:block]
DOMAIN,ads.example.test,REJECT|exact enabled|1
DOMAIN-SUFFIX,tracker.example.test,REJECT|suffix enabled|1
DOMAIN-SUFFIX,corp.example.test,REJECT|broad suffix with whitelisted child|1
DOMAIN, spaced.example.test , REJECT |trimmed fields|1
 dOmAiN-SuFfIx , MixedCase.example.test , reject |mixed-case type|1
DOMAIN,allowed.example.test,REJECT|whitelisted|1
DOMAIN,evilallowed.example.test,REJECT|boundary control|1
DOMAIN,pass.example.test,DIRECT|allow action|1
DOMAIN-KEYWORD,keywordad,REJECT|unsupported|1
IP-CIDR,192.0.2.0/24,REJECT|cidr|1
disabled.example.test|disabled|0
[list:domain]
allowed.example.test|allow|1
safe.corp.example.test|child allow|1
CONF
printf "%s\n" "subsafe.example.test" > "$T/cache/wlexc.tmp"
export PG="$T" CONF="$T/settings.conf"
sh -c '
  . "$1/scripts/util.sh"
  . "$1/scripts/vpncore.sh"
  vpncore_bin() { echo /bin/true; }
  vpncore_core_version() { echo 1.14.3; }
  _fixture_block=$(pg_list_enabled block)
  [ -n "$_fixture_block" ] || { echo "FAIL: fixture block list parsed empty (PG=$PG CONF=$CONF)" >&2; exit 31; }
  _fixture_dns_block=$(vpncore_dns_block_rules 1.14.3)
  printf "DNS-DIAG version=%s ge11=%s ge12=%s block=%s\\n" "$(vpncore_core_version /bin/true)" "$(vpncore_ver_ge 1.14.3 1.11 && echo yes || echo no)" "$(vpncore_ver_ge 1.14.3 1.12 && echo yes || echo no)" "$_fixture_dns_block" >&2
  [ -n "$_fixture_dns_block" ] || { echo "FAIL: DNS block rule compiler returned empty; entries: $_fixture_block" >&2; exit 32; }
  vpncore_dns_json 1.1.1.1 223.5.5.5 /bin/true "" > "$PG/dns-fragment.json"
  printf "DNS-DIAG after_json core=%s dnsver=%s block=%s whitelist=%s\\n" "$(vpncore_core_version /bin/true)" "${_dns_ver:-unset}" "${_dns_block_rules:-unset}" "${_dns_wl_rules:-unset}" >&2
  printf "{%s}\\n" "$(cat "$PG/dns-fragment.json")"
' sh "$ROOT" > "$T/config.json"
python3 - "$T/config.json" <<'PY'
import json, pathlib, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
rules=d["dns"]["rules"]
assert rules[0] == {"domain_suffix":["allowed.example.test"],"server":"remote"}, rules
assert rules[1] == {"domain_suffix":["safe.corp.example.test"],"server":"remote"}, rules
assert rules[2] == {"domain_suffix":["subsafe.example.test"],"server":"remote"}, rules
assert rules[-1] == {"domain_suffix":[".cn"],"server":"local"}, rules
assert {"domain":["ads.example.test"],"action":"reject"} in rules, rules
assert {"domain_suffix":["tracker.example.test"],"action":"reject"} in rules, rules
assert {"domain":["spaced.example.test"],"action":"reject"} in rules, rules
assert {"domain_suffix":["mixedcase.example.test"],"action":"reject"} in rules, rules
assert {"domain_suffix":["corp.example.test"],"action":"reject"} in rules, rules
assert rules.index({"domain_suffix":["safe.corp.example.test"],"server":"remote"}) < rules.index({"domain_suffix":["corp.example.test"],"action":"reject"}), rules
blocked = {d for r in rules if r.get("action") == "reject" for k in ("domain", "domain_suffix") for d in r.get(k, [])}
assert "allowed.example.test" not in blocked, rules
assert "evilallowed.example.test" in blocked, rules
assert not any(x in str(r) for r in rules for x in ("pass.example.test","keywordad","192.0.2.0/24","disabled.example.test")), rules
print("PASS: sing-box DNS block rules preserve exact/suffix semantics, whitelist boundary, enabled state and safe syntax")
PY
# Legacy cores before reject-action support must not receive unsupported DNS actions.
sh -c '
  . "$1/scripts/util.sh"
  . "$1/scripts/vpncore.sh"
  vpncore_bin() { echo /bin/true; }
  vpncore_core_version() { echo 1.10.0; }
  printf "{%s}\n" "$(vpncore_dns_json 1.1.1.1 223.5.5.5 /bin/true "")"
' sh "$ROOT" > "$T/legacy.json"
python3 - "$T/legacy.json" <<'PY'
import json, pathlib, sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert d["dns"]["rules"] == [
    {"domain_suffix":["allowed.example.test"],"server":"remote"},
    {"domain_suffix":["safe.corp.example.test"],"server":"remote"},
    {"domain_suffix":["subsafe.example.test"],"server":"remote"},
    {"domain_suffix":[".cn"],"server":"local"},
], d
print("PASS: legacy DNS schema preserves whitelist rules and omits unsupported reject actions")
PY
sh -n "$ROOT/scripts/vpncore.sh"
echo 'PASS: VPN DNS block rule generation regression'
