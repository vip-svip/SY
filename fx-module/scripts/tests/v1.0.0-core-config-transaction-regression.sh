#!/system/bin/sh
# Host-compatible static regression checks for atomic sing-box config generation/rollback.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
S="$ROOT/scripts/vpncore.sh"
assert() { grep -Fq "$1" "$S" || { echo "FAIL: missing: $1" >&2; exit 1; }; }
assert '_cfg_tmp="${_cfg}.tmp.$$"'
assert 'vpncore_check_conf "$_gc_bin" "$_cfg_tmp"'
assert 'mv -f "$_cfg_tmp" "$_cfg"'
assert '_cfg_backup="${_cfg}.previous.$$"'
assert '无法备份现有核心配置，拒绝启动并保留原配置'
assert 'if ! cp -p "$_cfg" "$_cfg_backup" 2>/dev/null || [ ! -s "$_cfg_backup" ]; then'
assert '运行预检失败，已恢复上一份核心配置'
assert '核心启动即退出，已恢复上一份核心配置'
assert '核心未就绪，已恢复上一份核心配置'
sh -n "$S"
echo 'PASS: core config transaction regression'
