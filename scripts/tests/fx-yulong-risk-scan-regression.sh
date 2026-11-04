#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
ACCESS="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java"
DISPATCH="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRiskScanDispatcher.java"
INSTALL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongInstallScanReceiver.java"
UI="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$ACCESS" "$DISPATCH" "$INSTALL" "$UI"; do [ -s "$file" ] || fail "auto-risk source missing: $file"; done
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
echo "PASS: Yulong auto-risk scan covers foreground and install events with bounded per-package cooldown and user-confirmed removal"
