#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
MANIFEST="$APP/AndroidManifest.xml"
ACTIVITY="$APP/java/roro/stellar/manager/authorization/FxStellarSecureSettingsActivity.java"
MANAGER="$APP/java/roro/stellar/manager/authorization/FxStellarManagerActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MANIFEST" "$ACTIVITY" "$MANAGER"; do
  [ -s "$file" ] || fail "missing Stellar secure-settings migration source: $file"
done
python3 - "$MANIFEST" "$ACTIVITY" "$MANAGER" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest_path, activity_path, manager_path = map(Path, sys.argv[1:])
manifest_text = manifest_path.read_text(encoding="utf-8")
activity = activity_path.read_text(encoding="utf-8")
manager = manager_path.read_text(encoding="utf-8")
root = ET.parse(manifest_path).getroot()
android = "{http://schemas.android.com/apk/res/android}"
permissions = {
    item.attrib.get(android + "name")
    for item in root.findall("uses-permission")
}
assert "android.permission.WRITE_SECURE_SETTINGS" in permissions, "FX must declare the permission before pm grant"
activities = {
    item.attrib.get(android + "name"): item
    for item in root.findall("./application/activity")
}
name = "roro.stellar.manager.authorization.FxStellarSecureSettingsActivity"
assert name in activities, "Stellar secure-settings page must be registered"
assert activities[name].attrib.get(android + "exported") == "false", "Root grant UI must remain private"
assert "FxStellarSecureSettingsActivity.class" in manager, "Stellar manager must expose the migrated grant page"
assert "RootAccess.execute(permissionCommand(grant)" in activity, "grant/revoke must use the FX Root bridge"
assert "pm grant" in activity and "pm revoke" in activity and "FX_PERMISSION_COMMAND_SUCCEEDED" in activity
assert "pm check-permission" not in activity, "do not depend on a non-portable pm check-permission command"
assert "FX_PERMISSION_VERIFIED" in activity and "permissionGranted() == grant" in activity, "grant/revoke must be verified, not assumed"
assert "WRITE_SECURE_SETTINGS" in activity and "明确授予" in activity and "明确撤销" in activity, "privileged permission changes require explicit user confirmation"
assert "new ArrayBlockingQueue<>(2)" in activity and "RejectedExecutionException" in activity
assert "worker.shutdownNow()" in activity, "Root worker must stop with Activity lifecycle"
assert "ACTION_APPLICATION_DEVELOPMENT_SETTINGS" in activity, "manual Wireless debugging settings route missing"
assert "mDNS" in activity and "libadb.so" in activity and "不会将打开开发者选项伪装成已配对" in activity, "unmigrated protocol boundary must remain truthful"
assert "roro.stellar.manager.authorization.FxStellarSecureSettingsActivity.class" in manager
print("PASS: Stellar secure-settings grant is Root-backed, user-confirmed, verified, revocable and explicitly distinct from automatic ADB pairing")
PY
