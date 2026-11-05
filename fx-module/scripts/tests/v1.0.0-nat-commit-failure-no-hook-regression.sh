#!/system/bin/sh
# Regression: nat queue failures must propagate, and a failed PGNAT commit must not hook OUTPUT.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
sh -n "$A"
# Ensure missing restore binaries are not silently treated as successful NAT commits.
grep -Fq 'if ! command -v "$_n_cmd" >/dev/null 2>&1; then' "$A"
grep -Fq '_nf_fail=1' "$A"
grep -Fq 'return "$_nf_fail"' "$A"
# A failed batch/fallback must prevent OUTPUT interception of a partial PGNAT chain.
awk '
  index($0, "if [ \"$ANY_NAT\" = \"1\" ]; then") { active=1 }
  active { print }
  index($0, "# ---------- 2c. VPN") && active { exit }
' "$A" > "${TMPDIR:-/tmp}/fx-nat-hook.$$.txt"
trap 'rm -f "${TMPDIR:-/tmp}/fx-nat-hook.$$.txt"' EXIT HUP INT TERM
B="${TMPDIR:-/tmp}/fx-nat-hook.$$.txt"
grep -Fq 'if [ "$_DNS_FW_FLUSH_OK" = "1" ] && nat_flush; then' "$B"
grep -Fq 'if nat4 -I OUTPUT -j PGNAT && { [ "$DNS_AGH_IPV6" != "1" ] || nat6 -I OUTPUT -j PGNAT; }; then' "$B"
grep -Fq 'pg_fail dns "防火墙或 PGNAT 提交失败；已跳过 OUTPUT 接管' "$B"
# The per-line fallback records failures instead of claiming success.
grep -Fq 'if iptables $FWWAIT -t nat $_n_ln 2>>"$PG/apply.log"; then' "$A"
grep -Fq 'if ip6tables $FWWAIT -t nat $_n_ln 2>>"$PG/apply.log"; then' "$A"
grep -Fq '_nf_line_fail=1' "$A"
echo 'FX NAT commit failure/no-hook regression: PASS'
