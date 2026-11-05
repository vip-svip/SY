#!/system/bin/sh
# Host-side static regression guard for raw-table PGNF hook ordering.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/scripts/apply.sh"
T="${TMPDIR:-/tmp}/fx-raw-netfilter-order-$$.txt"
trap 'rm -f "$T"' EXIT HUP INT TERM
awk '/^# ---------- 5d\. 网络过滤器加固 k_netfilter ----------/{on=1} on{print} on && /^# ---------- 6\. 生成 LSPosed 配置 ----------/{exit}' "$SRC" > "$T"
test -s "$T" || { echo 'FAIL: cannot extract k_netfilter section' >&2; exit 1; }
flush=$(grep -n 'if fw_flush' "$T" | head -1 | cut -d: -f1)
hook=$(grep -n 'iptables .* -t raw -A OUTPUT -j PGNF ' "$T" | head -1 | cut -d: -f1)
test -n "$flush" && test -n "$hook" || { echo 'FAIL: expected flush/hook sequence missing' >&2; exit 1; }
test "$flush" -lt "$hook" || { echo 'FAIL: raw OUTPUT hook occurs before queued rules flush' >&2; exit 1; }
grep -q 'PGNF/PGNF6 规则队列提交失败；未挂载 OUTPUT' "$T" || { echo 'FAIL: flush failure is not reported without hook activation' >&2; exit 1; }
grep -q 'ip6tables .* -t raw -C OUTPUT -j PGNF6' "$T" || { echo 'FAIL: IPv6 hook verification missing' >&2; exit 1; }
echo 'PASS: PGNF rules flush before hook activation; flush failure blocks hooks; both families verified'
