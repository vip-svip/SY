#!/system/bin/sh
# Regression: direct mode must not report clean when firewall tooling/table queries fail.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
# Missing tools must mark verification unknown rather than silently counting zero rules.
grep -Fq '_dir_verify_ok=1' "$A"
grep -Fq 'if ! command -v "$_ipt" >/dev/null 2>&1; then' "$A"
grep -Fq 'if ! _dir_rules=$("$_ipt" -t "$_t" -S 2>/dev/null); then' "$A"
grep -Fq 'direct 模式清理结果无法完整验证' "$A"
grep -Fq '不能报告已清理干净' "$A"
# Ensure the verifier does not regress to a pipeline that masks iptables -S exit status.
if grep -Fq '_left=$("$_ipt" -t "$_t" -S 2>/dev/null | grep -cE' "$A"; then
  echo 'FAIL: direct-mode verification masks firewall query failures'
  exit 1
fi
# Do not emit a success-looking direct-mode verification message after a failed
# verification branch; this previously contradicted pg_fail and confused diagnostics.
if grep -Fq 'pg_log "vpn: direct mode verified — PGVPN/PGVPN6/PGKS/PGBLK6 已清空，无接管规则"' "$A"; then
  echo 'FAIL: unconditional direct-mode success log remains after verifier failure'
  exit 1
fi
grep -Fq 'the verification branch above may have called pg_fail' "$A"
sh -n "$A"
echo 'FX VPN direct firewall verification failure regression: PASS'
