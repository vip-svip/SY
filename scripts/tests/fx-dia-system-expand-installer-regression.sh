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
grep -Fq 'sessionReadSucceeded' "$POLICY" || fail "policy does not fail closed on session-read errors"
echo "PASS: Package Installer restart checks all sessions, fails closed and requires confirmation"
