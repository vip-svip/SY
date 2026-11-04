#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACCESS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java"
DISPATCH="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRiskScanDispatcher.java"
INSTALL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongInstallScanReceiver.java"
UI="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java"
SCAN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanEngine.java"
CONTENT_DB="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusContentDb.java"
CONTENT_ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java"
COMPLETENESS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanCompleteness.java"
HOST_TEST="$ROOT/scripts/tests/FxYulongScanCompletenessHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$ACCESS" "$DISPATCH" "$INSTALL" "$UI" "$SCAN" "$CONTENT_DB" "$CONTENT_ACTIVITY" "$COMPLETENESS" "$HOST_TEST"; do
  [ -s "$file" ] || fail "auto-risk source missing: $file"
done
grep -Fq 'onForegroundPackageChanged(this, pkg)' "$ACCESS" || fail "foreground package events are not scanned"
grep -Fq 'onPackageInstalled' "$INSTALL" || fail "package install/update event path is missing"
grep -Fq 'onVirusDatabaseUpdated' "$DISPATCH" || fail "virus database updates must trigger a full installed-app scan"
grep -Fq 'FULL_SCAN_RUNNING' "$DISPATCH" || fail "full installed-app scan must be serialized"
grep -Fq 'FxYulongRiskScanDispatcher.onVirusDatabaseUpdated' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java" || fail "database screen does not trigger post-update full scan"
grep -Fq 'getLastSuccessAt() > previousContentSuccess' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java" || fail "content DB scan trigger must require a successful new/304 fetch"
grep -Fq 'FxYulongVirusDb.isServerReachable()' "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDatabaseActivity.java" || fail "list DB scan trigger must require a successful list fetch"
grep -Fq 'PACKAGE_COOLDOWN_MS' "$DISPATCH" || fail "per-package scan cooldown is missing"
grep -Fq 'auto_block_on' "$DISPATCH" || fail "original automatic risk master switch is not honored"
grep -Fq 'auto_block_mode' "$DISPATCH" || fail "original direct/confirm mode is not honored"
grep -Fq 'Intent.ACTION_DELETE' "$DISPATCH" || fail "direct mode must open Android's user-confirmed uninstall screen"
! grep -Eq 'pm[[:space:]]+uninstall|su[[:space:]]+-c' "$DISPATCH" || fail "auto-risk path must never uninstall silently"
grep -Fq 'getBoolean("automatic_install_scan_enabled", true)' "$UI" || fail "install scanning must preserve original default-on behavior"
grep -Fq 'autoRiskScan' "$UI" || fail "automatic foreground scan toggle is missing"
grep -Fq 'ACTION_ACCESSIBILITY_SETTINGS' "$UI" || fail "foreground scan must link to user-enabled accessibility"
grep -Fq 'public final int contentReadFailures' "$SCAN" || fail "content-scan read failures are not preserved"
grep -Fq 'verdict.unavailable' "$SCAN" || fail "unreadable APK input is silently treated as clean"
grep -Fq 'contentReadFailures++' "$SCAN" || fail "inspection exceptions are not reflected in scan status"
grep -Fq 'result.scanComplete' "$CONTENT_ACTIVITY" || fail "empty result UI does not distinguish incomplete scans"
grep -Fq 'FxYulongScanCompleteness.isComplete' "$SCAN" || fail "aggregate scan lacks fail-closed completeness logic"
grep -Fq 'this.unavailable = unavailable' "$CONTENT_DB" || fail "content verdict discards unreadable input state"
grep -Fq 'v != null && !v.truncated && !v.unavailable' "$CONTENT_DB" || fail "incomplete verdicts must not be cached as CLEAN"
grep -Fq 'r.truncated = true' "$CONTENT_DB" || fail "token-entry read failures must mark inspection incomplete"
grep -Fq 'if (apkSha == null) contentReadFailure = true' "$CONTENT_DB" || fail "APK SHA-256 read failure is still treated as a no-match"
grep -Fq 'contentReadFailure = true' "$CONTENT_DB" || fail "DEX/asset entry read failures are still treated as no-match"
grep -Fq 'boolean inspectionIncomplete = contentReadFailure || tokenTruncated' "$CONTENT_DB" || fail "aggregate content read failures do not reach the final verdict"
grep -Fq '内容文件读取失败，结果不完整' "$CONTENT_DB" || fail "failed content reads must return an unavailable verdict"
python3 - "$CONTENT_DB" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
start = s.index("static Verdict inspectApk")
end = s.index("public static String snapshotJson", start)
scan = s[start:end]
weak = scan.index("if (maxHigh == 0 && weak >= 2)")
incomplete = scan.index("boolean inspectionIncomplete = contentReadFailure || tokenTruncated")
assert weak > incomplete, "weak-signal warning must be produced after incomplete state is known"
assert "if (apkSha == null) contentReadFailure = true" in scan
assert scan.count("if (sha == null) {") >= 2
print("PASS: APK, DEX and asset hash failures prevent partial content scans from being cached as clean")
PY
python3 - "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanEngine.java" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "contentReadFailures = 0" in s
assert "contentTruncated, this.contentReadFailures" in s
assert "未完成的项目不能视为安全" in s
print("PASS: Shield scan reports partial APK-content inspection without claiming completion")
PY
echo "PASS: Yulong auto-risk scan covers foreground and install events with bounded per-package cooldown and user-confirmed removal"
