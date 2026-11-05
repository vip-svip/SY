#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
APPLY="$ROOT/scripts/apply.sh"
CONF="$ROOT/scripts/default.conf"
fail() { echo "FAIL: $*" >&2; exit 1; }
grep -Fq '按配置中的遥测域名列表执行 hosts 屏蔽；不拦截应用内敏感 API 调用' "$HTML" || fail 'privacy_leak claim missing'
grep -Fq '按配置的应用信息上报域名执行 hosts 屏蔽；不等同于系统 API 级隐藏' "$HTML" || fail 'app_info claim missing'
grep -Fq '按配置的应用列表上报域名执行 hosts 屏蔽；不阻止本地 API 采集' "$HTML" || fail 'app_list_upload claim missing'
grep -Fq '按配置的使用统计域名执行 hosts 屏蔽；不覆盖所有应用统计接口' "$HTML" || fail 'usage_upload claim missing'
grep -Fq '按配置的诊断上报域名执行 hosts 屏蔽；不保证阻止所有崩溃/诊断上传' "$HTML" || fail 'diag_upload claim missing'
grep -Fq '阻断 TR-069 常用 TCP 7547/7548 端口；不加密流量或隐藏 SNI' "$HTML" || fail 'isp_snoop claim missing'
grep -Fq '阻断 SSDP/mDNS/NetBIOS 常用端口；不清理 HTTP 请求指纹' "$HTML" || fail 'net_privacy claim missing'
grep -Fq 'pg_log "fw: isp_snoop TR-069 7547/7548 dropped"' "$APPLY" || fail 'TR-069 backend implementation missing'
grep -Fq 'hosts: merged [$sect] domain blocklist' "$APPLY" || fail 'domain-list hosts consumer missing'
grep -Fq '[conf:app_list_upload]' "$CONF" || fail 'app-list upload config section missing'
echo 'PASS: privacy feature claims match implemented mechanisms'
