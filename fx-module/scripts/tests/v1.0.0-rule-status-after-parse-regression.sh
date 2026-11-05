#!/system/bin/sh
# Audit103 in-place update: rule status should be written after parser execution.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1],encoding='utf-8').read()
start=s.index('hosts_parse_file "$_F" "$_FIP" "$WL_EXC"')
status=s.index('record rule "$_entry" partial "下载与当前解析阶段完成；最终系统应用/实际拦截尚未确认"', start)
assert status > start, 'status should be recorded after parsing'
assert 'if ! hosts_parse_file' in s, 'parser command failure should be checked'
assert '解析出 $_parsed_ip_lines 条 IP-CIDR' in s, 'status should include parsed IP-CIDR count'
assert 'record rule "$_entry" partial "下载成功；解析与实际应用尚未由此状态确认"' not in s, 'old premature status remains'
PY
echo 'PASS: rule status follows parser stage and distinguishes final application'
