#!/system/bin/sh
# Audit98: firewall rule logging must not claim IP rules are dropped before commit/hook verification.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
A="$ROOT/scripts/apply.sh"
awk '/# FX 规则（防火墙部分）/{p=1} p{print} p && /^# Hook 拦截/{exit}' "$A" > "${TMPDIR:-/tmp}/fx-fw-audit98.$$.txt"
T="${TMPDIR:-/tmp}/fx-fw-audit98.$$.txt"
trap 'rm -f "$T"' EXIT HUP INT TERM
grep -Fq '_FX4_QUEUED=0; _FX6_QUEUED=0; _FX_ADD_FAIL=0' "$T"
grep -Fq 'final activation depends on firewall batch commit and OUTPUT hook verification' "$T"
grep -Fq 'pg_fail fx "FX IP-CIDR 部分规则未能加入防火墙待提交链' "$T"
if grep -Fq 'fx IP-CIDR x$FXN dropped' "$T"; then echo 'FAIL: code claims dropped before final activation'; exit 1; fi
# Ensure each address family increments its own queued count only when the add call succeeds.
grep -Fq 'then _FX6_QUEUED=$((_FX6_QUEUED+1)); else _FX_ADD_FAIL=$((_FX_ADD_FAIL+1)); fi' "$T"
grep -Fq 'then _FX4_QUEUED=$((_FX4_QUEUED+1)); else _FX_ADD_FAIL=$((_FX_ADD_FAIL+1)); fi' "$T"
sh -n "$A"
echo 'PASS: FX firewall diagnostics distinguish queued rules, add failures, and final activation'
