#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A=$(mktemp "${TMPDIR:-/tmp}/fx-local-recursive-agh.XXXXXX")
U=$(mktemp "${TMPDIR:-/tmp}/fx-local-recursive-unbound.XXXXXX")
trap 'rm -f "$A" "$U"' EXIT HUP INT TERM
sh "$ROOT/scripts/adguardhome.sh" render-config "$ROOT" /tmp > "$A"
sh "$ROOT/scripts/unbound.sh" render-config "$ROOT" /tmp > "$U"
# AGH's sole upstream must be loopback Unbound, never a cloud resolver.
grep -Fq '127.0.0.1:5353' "$A"
if grep -Eiq 'tls://|https://|quic://|bootstrap_dns|1\.1\.1\.1|8\.8\.8\.8|223\.5\.5\.5|114\.114\.114\.114' "$A"; then
  echo 'FAIL: public recursive DNS forwarder/bootstrap leaked into AdGuard Home config' >&2; exit 1
fi
# The recursive resolver must bind loopback only and start from root hints + trust anchor.
grep -Fq 'interface: 127.0.0.1' "$U"
grep -Fq 'port: 5353' "$U"
grep -Fq 'access-control: 127.0.0.0/8 allow' "$U"
grep -Fq 'root-hints:' "$U"
grep -Fq 'auto-trust-anchor-file:' "$U"
grep -Fq 'module-config: "validator iterator"' "$U"
grep -Fq 'qname-minimisation: yes' "$U"
grep -Fq 'aggressive-nsec: yes' "$U"
grep -Fq 'prefetch: yes' "$U"
grep -Fq 'serve-expired: yes' "$U"
if grep -Eiq '^  (forward-zone|forward-addr|forward-host|forward-first):' "$U"; then
  echo 'FAIL: Unbound config is forwarding instead of recursing' >&2; exit 1
fi
# The frontend still only imports the six scoped anti-fraud/96110 candidate rules, not ad/splash/watermark rules.
[ "$(grep -c '^  - "||' "$A")" -eq 5 ]
for d in gjfzpt.cn fzapp-test-tyy.gjfzpt.cn oss.gjfzpt.cn fzapp.gjfzpt.cn fzapph5.gjfzpt.cn; do grep -Fq "||$d^" "$A"; done
if grep -Eiq 'ads|advert|splash|watermark|open.?screen|IP-CIDR|PACKAGE-NAME|DOMAIN-KEYWORD' "$A"; then
  echo 'FAIL: non anti-fraud rule leaked into local DNS filtering config' >&2; exit 1
fi
grep -q 'dns_engine_adguardhome=1' "$ROOT/scripts/default.conf"
! grep -Fq 'data-key="dns_engine_adguardhome"' "$ROOT/webroot/index.html"
grep -q 'Legacy saved dns_engine_adguardhome=0' "$ROOT/scripts/apply.sh"
grep -q 'unbound.sh" ensure' "$ROOT/scripts/adguardhome.sh"
grep -q 'unbound.sh" stop' "$ROOT/scripts/adguardhome.sh"
grep -q 'narrow root-owned UDP/TCP 53 recursive DNS exemptions' "$ROOT/scripts/apply.sh"
if sed -n '2125,2190p;3080,3110p' "$ROOT/scripts/apply.sh" | grep -Fq -- '-m owner --uid-owner 0 -j RETURN'; then echo 'FAIL: local DNS integration contains a blanket UID-0 bypass' >&2; exit 1; fi
echo 'PASS: automatic local AGH cache/filter -> loopback Unbound recursion; no fixed public forwarding DNS; anti-fraud-only rules; DNSSEC/root hints; fail-open lifecycle'
