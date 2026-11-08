#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MANAGER="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/FxStellarManagerActivity.java"
ACTIVITY="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/FxStellarCommandShortcutActivity.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
CONTROL="$ROOT/scripts/yulong-stellar-control.sh"
for file in "$MANAGER" "$ACTIVITY" "$MANIFEST" "$CONTROL"; do
  [ -s "$file" ] || { echo "FAIL: missing Stellar shortcut migration source: $file" >&2; exit 1; }
done
python3 - "$MANAGER" "$ACTIVITY" "$MANIFEST" "$CONTROL" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manager, activity, manifest_path, control = map(lambda p: Path(p).read_text(encoding="utf-8"), sys.argv[1:])
assert "ShortcutManager" in manager and "requestPinShortcut" in manager
assert "ShortcutInfo.Builder" in manager and "setIntent(launch)" in manager
assert "MAX_COMMAND_SHORTCUTS = 24" in manager
assert "packages.contains(packageName)" in manager, "only a Stellar-authorized target app may receive a shortcut"
assert "scopes.contains(packageName+\"|\"+scope)" in manager, "shortcut creation must require the selected read-only scope"
assert "always.contains(packageName+\"|\"+command)" in manager, "shortcut creation must require the exact always-allowed command"
assert "isReadOnlyScope(scope)" in manager and "isReadOnlyCommand(command)" in manager
assert "pinReadOnlyCommandShortcut(target,scope,c)" in manager

assert "ACTION_EXECUTE_COMMAND_SHORTCUT" in activity
assert "getStringExtra(\"command_id\")" in activity and "[A-Fa-f0-9]{32}" in activity
assert "fx_stellar_command_shortcuts" in activity
assert "validPackage(packageName)" in activity and "validScope(scope)" in activity
assert "validReadOnlyCommand(command)" in activity
assert "new ArrayBlockingQueue<>(1)" in activity and "RejectedExecutionException" in activity
assert "RootAccess.execute(" in activity and "yulong-stellar-control.sh" in activity
assert '\"run \" + quote(packageName)' in activity
assert '.setPositiveButton(\"执行\"' in activity, "shortcut execution must require explicit foreground confirmation"
assert "worker.shutdownNow()" in activity
assert "new ProcessBuilder" not in activity and "Runtime.getRuntime()" not in activity
assert activity.count("protected void onCreate(Bundle saved)") == 1, "shortcut Activity must not contain duplicate onCreate bodies"
assert activity.count("private void executeCommand()") == 1, "shortcut Activity must not contain duplicate command executors"
assert activity.rstrip().endswith("}"), "shortcut Activity must end at its single class boundary"

root = ET.parse(sys.argv[3]).getroot()
ns = "{http://schemas.android.com/apk/res/android}"
node = next((n for n in root.findall("./application/activity")
             if n.attrib.get(ns+"name") == "roro.stellar.manager.authorization.FxStellarCommandShortcutActivity"), None)
assert node is not None, "pinned shortcut Activity is not registered"
assert node.attrib.get(ns+"exported") == "false", "shortcut executor must not be callable by arbitrary apps"

assert "has_scope(){" in control and "has_always(){" in control
assert "valid_command(){" in control and "run_readonly(){" in control
assert 'has_always \"$pkg\" \"$command\"' in control
assert "required Stellar capability is not granted" in control
print("PASS: Stellar pinned shortcuts bind only granted read-only commands, require per-run confirmation and retain server-side permission checks")
PY
