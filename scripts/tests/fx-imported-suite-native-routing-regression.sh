#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$MAIN" ] || fail "MainActivity source missing"
grep -Fq 'private void handleImportedNativeTabIntent(Intent intent)' "$MAIN" || fail "native-tab shortcut handler missing"
grep -Fq 'if (tab >= 0 && tab <= 3) openImportedNativeTab(tab);' "$MAIN" || fail "native tab shortcut is not range-checked"
grep -Fq 'handleImportedNativeTabIntent(getIntent());' "$MAIN" || fail "cold-start native tab route missing"
grep -Fq 'handleImportedNativeTabIntent(intent);' "$MAIN" || fail "singleTop native tab route missing"
grep -Fq 'case "VPN 保护": case "VPN 状态": case "自动重连":' "$MAIN" || fail "Yulong VPN feature group not routed"
grep -Fq 'FxYulongAdGeneralActivity.class' "$MAIN" || fail "Yulong general settings do not open their native page"
grep -Fq 'FxYulongAdSummaryActivity.class' "$MAIN" || fail "Yulong summary/statistics do not open their native page"
grep -Fq 'FxYulongDnsActivity.class' "$MAIN" || fail "Yulong DNS query log does not open its native page"
grep -Fq 'page.equals("计划任务")' "$MAIN" || fail "Yulong schedule route is missing"
grep -Fq 'putExtra("suite_page", "计划任务")' "$MAIN" || fail "Yulong schedule does not open its own editor"
grep -Fq 'page.equals("白名单域名")' "$MAIN" || fail "Yulong domain allow/block route is missing"
grep -Fq 'putExtra("suite_page", "域名名单")' "$MAIN" || fail "Yulong custom domains do not open domain editor"
grep -Fq 'page.equals("DNS 日志")' "$MAIN" || fail "Yulong DNS log route is missing"

grep -Fq 'case "信任的网络":' "$MAIN" || fail "Yulong trusted Wi-Fi source page is not mapped"
trusted_block=$(sed -n '/case "信任的网络":/,/case "Root 代理模式":/p' "$MAIN")
printf '%s\\n' "$trusted_block" | grep -Fq '"suite_page", "信任的网络"' || fail "trusted Wi-Fi does not open its dedicated native screen"
printf '%s\\n' "$trusted_block" | grep -Fq 'VPN 与 Root Proxy' && fail "trusted Wi-Fi is still routed to Root Proxy"

vpn_block=$(sed -n '/case "VPN 保护": case "VPN 状态": case "自动重连":/,/case "信任的网络":/p' "$MAIN")
printf '%s\n' "$vpn_block" | grep -Fq '"fx_open_native_tab", 0' || fail "Yulong VPN controls do not open FX native VPN tab"
printf '%s\n' "$vpn_block" | grep -Fq 'FLAG_ACTIVITY_CLEAR_TOP' || fail "native VPN route may create a duplicate MainActivity"
quic_block=$(sed -n '/case "过滤 HTTP\/3 (QUIC)":/,/case "HTTPS 过滤":/p' "$MAIN")
printf '%s\n' "$quic_block" | grep -Fq '"suite_page", "DNS 设置"' || fail "QUIC policy is not routed to DNS filtering controls"
printf '%s\n' "$quic_block" | grep -Fq 'FxYulongAdActivity.class' || fail "QUIC policy page is not native"
printf '%s\n' "$quic_block" | grep -Fq 'showNativeCertificateManager' && fail "QUIC policy still opens certificate management"
shield_status=$(sed -n '/case "守护运行状态":/,/case "每日安全总结":/p' "$MAIN")
printf '%s\n' "$shield_status" | grep -Fq 'FxYulongShieldActivity.class' || fail "live guardian status must open Shield hub/status"
daily_summary=$(sed -n '/case "每日安全总结":/,/case "完整性校验":/p' "$MAIN")
printf '%s\n' "$daily_summary" | grep -Fq 'FxYulongDailySummaryActivity.class' || fail "daily summary lost its dedicated native page"
rescue=$(sed -n '/case "悬浮救援入口":/,/case "守护运行状态":/p' "$MAIN")
printf '%s\n' "$rescue" | grep -Fq 'FxYulongShieldActivity.class' || fail "floating rescue settings must open the page with the real enable switch"
grep -Fq 'FxYulongRescueActivity.class' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java" || fail "Shield rescue center is no longer reachable from the hub"
grep -Fq '打开救援中心' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java" || fail "hub no longer exposes the original rescue center entry"
echo "PASS: Yulong VPN, QUIC, Shield rescue and live-status routes use the matching native feature pages"
