#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
JAVA="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$JAVA" ] || { echo "FAIL: MainActivity.java missing" >&2; exit 1; }
python3 - "$JAVA" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")

def method(signature):
    start = source.find(signature)
    assert start >= 0, f"missing method: {signature}"
    end = source.find("\n    }", start)
    assert end >= 0, f"method body is not closed: {signature}"
    return source[start:end + 6]

back = method("@Override public void onBackPressed()")
ordered = [
    "if (hookTargetVisible)",
    "if (migrationChildActive",
    "if (migrationLevel >= 3",
    "if (migrationLevel == 2",
    "if (migrationLevel == 1",
    "if (settingsUiVisible)",
    "if (hookUiVisible",
    "if (hookHubVisible)",
]
positions = [back.find(token) for token in ordered]
assert all(position >= 0 for position in positions), f"Back stack branch missing: {dict(zip(ordered, positions))}"
assert positions == sorted(positions), "Back stack precedence is incorrect; target/child pages must return before suite/root handling"

saved = method("@Override protected void onSaveInstanceState(Bundle outState)")
for key in ("fx_migration_suite", "fx_migration_category", "fx_migration_page",
            "fx_migration_level", "fx_migration_child_active"):
    assert key in saved, f"migration navigation state is not saved: {key}"

created = method("@Override public void onCreate(Bundle state)")
assert 'state.getString("fx_migration_suite")' in created
assert 'state.getBoolean("fx_migration_child_active", false)' in created
assert "restoreMigrationNavigation();" in created

restore = method("private void restoreMigrationNavigation()")
for marker in ("migrationChildActive", "openImportedSuitePage(suite, category, page)",
               "showImportedSuitePendingPage", "showImportedSuiteCategory",
               "showImportedSuite(migrationSuite)"):
    assert marker in restore, f"recreation cannot restore migration state: {marker}"

suite = method("private void showImportedSuite(String suite)")
category = method("private void showImportedSuiteCategory(String suite, String category)")
pending = method("private void showImportedSuitePendingPage(String suite, String category, String page, String detail)")
assert 'migrationLevel = 1;' in suite
assert 'migrationLevel = 2;' in category
assert 'migrationLevel = 3;' in pending

route = method("private void openImportedSuitePage(String suite, String category, String page)")
assert route.count("markMigrationChild(suite, category, page);") >= 10,     "Dia same-Activity child routes are not consistently bound to their migration return path"

clear = method("private void clearMigrationNavigation()")
for name in ("migrationSuite = null", "migrationCategory = null", "migrationPage = null",
             "migrationLevel = 0", "migrationChildActive = false"):
    assert name in clear, f"leaving migration screens does not clear {name}"

handler = method("private void handleNativeTabSelection(int index)")
hook_tab = handler.split("else if (index == 4)", 1)[1].split("else if (index >= 0", 1)[0]
assert "clearMigrationNavigation();" in hook_tab and hook_tab.index("clearMigrationNavigation();") < hook_tab.index("showAppList();"), \
    "opening the top-level Hook tab must leave the imported-suite return stack"
print("PASS: imported-suite Android Back hierarchy, same-Activity child return, and Activity recreation state")
PY
