#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$ACTIVITY" ] || fail "Yulong Ad Activity missing"
grep -Fq 'private void refreshRootProxyStatus()' "$ACTIVITY" || fail "native Root Proxy live status panel missing"
grep -Fq 'root("rootproxy-status", result ->' "$ACTIVITY" || fail "status panel is not backed by module status command"
grep -Fq 'values.getOrDefault("active", "unknown")' "$ACTIVITY" || fail "configured enable state is not distinguished from actual DNS takeover"
grep -Fq 'values.getOrDefault("interface", "未知")' "$ACTIVITY" || fail "active VPN interface is not displayed"
grep -Fq 'values.getOrDefault("vpn_uid", "未知")' "$ACTIVITY" || fail "active VPN owner UID is not displayed"
grep -Fq 'values.getOrDefault("egress_ipv4", "未知")' "$ACTIVITY" || fail "validated DNS egress address is not displayed"
grep -Fq 'if ("VPN 与 Root Proxy".equals(page)) refreshRootProxyStatus();' "$ACTIVITY" || fail "Root Proxy status is not refreshed after saving DNS/VPN options"
grep -Fq '第二个 VpnService 不会启动' "$ACTIVITY" || fail "single VPN/TUN architecture notice missing"
echo "PASS: Yulong Root Proxy UI distinguishes configured state from live DNS takeover and shows validated VPN path"
