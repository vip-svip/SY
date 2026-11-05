#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
T="${TMPDIR:-/tmp}/fx-vpn-port-probe-$$.txt"
trap 'rm -f "$T"' EXIT HUP INT TERM
awk '/^[[:space:]]*vpn_port_open\(\)/,/^[[:space:]]*}/ {print}' "$SRC" > "$T"
test -s "$T"
grep -q '_vpn_curl_rc=.*' "$T"
grep -q '\[ "\$_vpn_curl_rc" -eq 0 \].*return 0' "$T"
grep -q 'curl 端口探测失败 rc=' "$T"
grep -q 'return 1' "$T"
grep -q '无 netstat/ss/curl' "$T"
# Regression guard: the old permissive branch and its “assume listening” behavior must be absent.
! grep -q 'case \$? in 7|28) return 1 ;; esac' "$T"
! grep -q '假定 .*已监听' "$T"
echo 'PASS: VPN port probe fails closed on curl errors and missing probes'
