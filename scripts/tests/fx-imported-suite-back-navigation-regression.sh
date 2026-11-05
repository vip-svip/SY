#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$JAVA" ] || { echo "FAIL: MainActivity.java missing" >&2; exit 1; }
python3 - "$JAVA" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

# Source APK names are development provenance only. The old source-app hub and
# its nested migration stack must not ship in the unified FX product UI.
for obsolete in (
    "migrationSuite", "migrationCategory", "migrationPage", "migrationLevel",
    "migrationChildActive", "clearMigrationNavigation", "markMigrationChild",
    "restoreMigrationNavigation", "showImportedSuite", "showImportedSuiteCategory",
    "openImportedSuitePage", "showImportedSuitePendingPage", "importedSuiteTitle",
    "importedSuiteSections", "addDiaActivationBanner", "迁移应用"
):
    assert obsolete not in source, f"legacy source-app navigation remains: {obsolete}"

# The DEX import flow must return to the actual Hook target/app-list hierarchy.
assert "activePrivacySection = \"自定义 Hook\";" in source
assert "showTarget(targetInfo);" in source
assert "migrationChildActive = true;" not in source

# Source capabilities remain integrated in the actual business destinations.
for token in (
    "FxYulongAdActivity.class", "FxYulongAdGeneralActivity.class",
    "FxYulongAdSummaryActivity.class", "FxYulongDnsActivity.class",
    "FxYulongFirewallActivity.class", "FxYulongAppWhitelistActivity.class"
):
    assert token in source, f"Ad page no longer exposes migrated feature: {token}"
privacy_start = source.index("private void buildNativePrivacyPage()")
privacy_end = source.index("private void refreshNativePrivacyStatus(", privacy_start)
assert "FxYulongShieldActivity.class" in source[privacy_start:privacy_end]
assert "FxDiaFridaActivity.class" in source, "Dia/Frida tools must remain inside Hook"
assert "FxDiaScriptLibraryActivity.class" in source, "Frida scripts must remain inside Script"
assert "Ad/Hosts" not in source and "Ad / Hosts" not in source
assert 'case 1: return "pageAd";' in source
assert 'case "pageHosts": tab = "ad"; break;' in source
print("PASS: no source-app migration hub; migrated features stay in Ad/Privacy/Hook/Script; Ad is the only second-tab label.")
PY
