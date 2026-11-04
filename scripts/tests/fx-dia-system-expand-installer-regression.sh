#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
DIA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia"
ACTIVITY="$DIA/FxDiaSystemExpandActivity.java"
POLICY="$DIA/FxDiaInstallerRestartPolicy.java"
UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaInstallerRestartPolicyTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$ACTIVITY" "$POLICY" "$UNIT"; do [ -s "$f" ] || fail "installer restart source missing: $f"; done
grep -Fq 'getAllSessions()' "$ACTIVITY" || fail "all installer sessions are not inspected"
grep -Fq 'session.isActive()' "$ACTIVITY" || fail "active install sessions are not detected"
grep -Fq 'session.isCommitted()' "$ACTIVITY" || fail "committed install sessions are not detected"
grep -Fq 'session.isStagedSessionActive()' "$ACTIVITY" || fail "active staged sessions are not detected"
grep -Fq 'if (!safe)' "$ACTIVITY" || fail "unsafe session state does not block restart"
grep -Fq 'RootAccess.execute(' "$ACTIVITY" || fail "restart does not use the native Root broker"
grep -Fq 'setPositiveButton("确认重启"' "$ACTIVITY" || fail "restart lacks explicit user confirmation"
grep -Fq 'openPackageInstallerAppInfo(packageName)' "$ACTIVITY" || fail "safe app-info fallback was removed"
grep -Fq 'FxDiaInstallerRestartPolicy.isSafeToRestart' "$ACTIVITY" || fail "UI bypasses tested restart policy"
[ "$(grep -Fc 'getAllSessions()' "$ACTIVITY")" -ge 2 ] || fail "install sessions are not rechecked after confirmation"
grep -Fq '确认窗口打开后检测到新的活动/已提交安装会话' "$ACTIVITY" || fail "session changes during confirmation are not refused"
grep -Fq 'sessionReadSucceeded' "$POLICY" || fail "policy does not fail closed on session-read errors"
grep -Fq '搜索应用名称或包名' "$ACTIVITY" || fail "install-source picker has no search field"
grep -Fq 'adapter.getFilter().filter' "$ACTIVITY" || fail "install-source picker does not filter labels/package names"
grep -Fq 'list.setEmptyView(empty)' "$ACTIVITY" || fail "install-source picker has no filtered empty state"
grep -Fq 'list.setOnItemClickListener' "$ACTIVITY" || fail "filtered rows do not open Android's per-app permission page"
if grep -Fq '.setItems(labels' "$ACTIVITY"; then fail "old unsearchable item dialog remains"; fi
echo "PASS: Package Installer restart checks all sessions, fails closed and requires confirmation"
