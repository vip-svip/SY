#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-agh-regress-$$.yaml
trap 'rm -f "$TMP"' EXIT HUP INT TERM

# The engine is automatic when safe prerequisites pass; its generated rules stay anti-fraud-only.
grep -qx 'dns_engine_adguardhome=1' "$ROOT/scripts/default.conf"
! grep -Fq 'data-key="dns_engine_adguardhome"' "$ROOT/webroot/index.html"
grep -Fq 'Local recursive DNS is automatic by default' "$ROOT/scripts/apply.sh"
sh "$ROOT/scripts/adguardhome.sh" render-config "$ROOT" /tmp > "$TMP"
cmp -s "$TMP" "$ROOT/docs/AdGuardHome-FX-runtime-config-v1.0.0.yaml" || { echo 'FAIL: documented AdGuard Home config differs from runtime generator' >&2; exit 1; }
[ "$(grep -c '^  - "||' "$TMP")" -eq 5 ]
grep -q '||gjfzpt.cn^' "$TMP"
grep -q '||fzapp-test-tyy.gjfzpt.cn^' "$TMP"
grep -q '||oss.gjfzpt.cn^' "$TMP"
grep -q '||fzapp.gjfzpt.cn^' "$TMP"
grep -q '||fzapph5.gjfzpt.cn^' "$TMP"
if grep -Eiq 'ads|advert|splash|watermark|open.?screen|IP-CIDR|PACKAGE-NAME|DOMAIN-KEYWORD' "$TMP"; then
  echo 'FAIL: non-domain/ad/open-screen/package/IP rule leaked into AdGuard Home DNS rules' >&2
  exit 1
fi
# Security/lifecycle requirements must remain explicit.
grep -q 'address: 127.0.0.1:0' "$TMP"
grep -q 'enabled: false' "$TMP"
grep -q 'password: "\$2a\$12\$' "$TMP"
grep -q '127.0.0.1:5353' "$TMP"
if grep -Eiq 'tls://|bootstrap_dns|223.5.5.5|tls://dns.alidns.com|tls://one.one.one.one' "$TMP"; then echo 'FAIL: local DNS frontend still forwards to a public resolver' >&2; exit 1; fi
grep -q 'root-hints:' "$ROOT/scripts/unbound.sh"
grep -q 'auto-trust-anchor-file:' "$ROOT/scripts/unbound.sh"
grep -q 'fx-dns-probe' "$ROOT/scripts/unbound.sh"
grep -q 'unbound.sh.*ensure' "$ROOT/scripts/adguardhome.sh"

grep -q 'narrow root-owned UDP/TCP 53 recursive DNS exemptions' "$ROOT/scripts/apply.sh"
if sed -n '2125,2190p;3080,3110p' "$ROOT/scripts/apply.sh" | grep -Fq -- '-m owner --uid-owner 0 -j RETURN'; then echo 'FAIL: local DNS integration contains a blanket UID-0 bypass' >&2; exit 1; fi
grep -q 'ip6tables.*--uid-owner 0 -p udp --dport 53 -j RETURN' "$ROOT/scripts/apply.sh"
grep -q 'fw4 -I PGUARD 1 -m owner --uid-owner 0 -p udp --dport 53 -j RETURN' "$ROOT/scripts/apply.sh"
grep -q 'fw6 -I PGUARD 1 -m owner --uid-owner 0 -p udp --dport 53 -j RETURN' "$ROOT/scripts/apply.sh"
grep -q -- '--check-config' "$ROOT/scripts/adguardhome.sh"
grep -q 'sha256sum' "$ROOT/scripts/adguardhome.sh"
grep -q '_pg_dns_probe' "$ROOT/scripts/adguardhome.sh"
grep -q 'DNS_SAFE="127.0.0.1"' "$ROOT/scripts/apply.sh"
grep -q -- "-j DNAT --to-destination '\[::1\]:53'" "$ROOT/scripts/apply.sh"
grep -q 'vpn_mode direct' "$ROOT/scripts/apply.sh"
grep -q 'external tunnel.*detected' "$ROOT/scripts/apply.sh"
grep -q 'adguardhome.sh.* stop' "$ROOT/uninstall.sh"
(
  cd "$ROOT/engines/adguardhome"
  sha256sum -c AdGuardHome-android-arm64.sha256 >/dev/null
)
echo 'PASS: automatic local DNS engine, six scoped anti-fraud/96110 candidate domain rules, checksums, recursive health gate, dual-stack redirect and uninstall lifecycle'
