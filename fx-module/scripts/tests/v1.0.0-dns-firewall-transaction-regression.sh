#!/system/bin/sh
# Regression: PGNAT must not be attached unless both firewall and NAT queues commit.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
sh -n "$A"
B="${TMPDIR:-/tmp}/fx-dns-fw-transaction.$$.txt"
trap 'rm -f "$B"' EXIT HUP INT TERM
awk '
  index($0, "if [ \"$ANY_NAT\" = \"1\" ]; then") { active=1 }
  active { print }
  index($0, "# ---------- 2c. VPN") && active { exit }
' "$A" > "$B"
grep -Fq '_DNS_FW_FLUSH_OK=1' "$B"
grep -Fq 'fw_flush 2>/dev/null || _DNS_FW_FLUSH_OK=0' "$B"
grep -Fq 'if [ "$_DNS_FW_FLUSH_OK" = "1" ] && nat_flush; then' "$B"
! grep -Fq '  if nat_flush; then' "$B"
! grep -Fq '  if nat_flush; then' "$B"
grep -Fq 'if nat4 -I OUTPUT -j PGNAT && { [ "$DNS_AGH_IPV6" != "1" ] || nat6 -I OUTPUT -j PGNAT; }; then' "$B"
awk 'index($0,"if [ \"$_DNS_FW_FLUSH_OK\" = \"1\" ] && nat_flush; then"){a=NR} index($0,"if nat4 -I OUTPUT -j PGNAT &&"){b=NR} END{exit !(a>0 && b>a)}' "$B"
grep -Fq '防火墙或 PGNAT 提交失败；已跳过 OUTPUT 接管' "$B"
echo 'FX DNS/firewall transaction regression: PASS'
