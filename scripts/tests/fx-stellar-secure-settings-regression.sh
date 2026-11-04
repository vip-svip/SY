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
assert 'grant ? "grant" : "revoke"' in activity and '+ "pm " + op + ' in activity and "FX_PERMISSION_COMMAND_SUCCEEDED" in activity, "grant/revoke command must map both user-confirmed operations through the Root backend"
assert "pm check-permission" not in activity, "do not depend on a non-portable pm check-permission command"
assert "FX_PERMISSION_COMMAND_SUCCEEDED" in activity and "permissionGranted() == grant" in activity, "grant/revoke must be verified, not assumed"
assert "WRITE_SECURE_SETTINGS" in activity and "明确授予" in activity and "明确撤销" in activity, "privileged permission changes require explicit user confirmation"
assert "new ArrayBlockingQueue<>(2)" in activity and "RejectedExecutionException" in activity
assert "worker.shutdownNow()" in activity, "Root worker must stop with Activity lifecycle"
assert "ACTION_APPLICATION_DEVELOPMENT_SETTINGS" in activity, "manual Wireless debugging settings route missing"
assert "原版无线 ADB 配对" in activity and "AdbPairingActivity.class" in activity, "migrated pairing screen must be reachable from Stellar secure settings"
assert "TLS 1.3" in activity and "SPAKE2" in activity and "PeerInfo" in activity and "mDNS" in activity, "secure settings must disclose the migrated pairing protocol"
assert "API 31+" in activity and "配对成功不会自动授予 WRITE_SECURE_SETTINGS" in activity, "pairing version boundary and separate permission grant must remain explicit"
assert "Android 11 及更旧系统不支持本页的 FX 独立主机密钥自动配对" in activity, "legacy system ADB pairing must not be presented as FX host-key pairing"
assert "系统自带 ADB 客户端的手动配对不会登记 FX 密钥" in activity, "manual pairing with the system adb identity must not be represented as FX pairing"
assert "_adb-tls-connect._tcp" in activity and "自动发现和端点保存" in activity, "migrated ADB connect DNS-SD endpoint discovery must be disclosed"
assert "一次性固定只读 echo Shell 探测" in activity, "completed fixed read-only ADB shell probe must be disclosed"
assert "原版通用 Shell 命令" in activity and "root: 通道" in activity and "tcpip 管理操作尚未迁入" in activity, "remaining original ADB management operations must remain explicitly unmigrated"
assert "固定探测成功不代表这些完整管理能力已完成" in activity, "one-shot probe must not be represented as full Shell migration"
assert "runPermissionChange(true)" in activity and "明确授予" in activity, "secure-settings grant must remain a separate user-confirmed action"
assert "new Intent(this,FxStellarSecureSettingsActivity.class)" in manager
print("PASS: Stellar secure-settings grant is Root-backed, user-confirmed, verified, revocable and explicitly distinct from automatic ADB pairing")
PY
