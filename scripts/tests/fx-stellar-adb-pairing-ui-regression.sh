#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
PAIRING="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/AdbPairingActivity.java"
DISCOVERY="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/AdbPairingDiscovery.java"
CLIENT="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/AdbPairingClient.java"
SECURE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/FxStellarSecureSettingsActivity.java"
EXPORTER="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/AdbTlsKeyingMaterial.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MANIFEST" "$PAIRING" "$DISCOVERY" "$CLIENT" "$SECURE" "$EXPORTER"; do
    [ -s "$file" ] || fail "ADB pairing migration source missing: $file"
done
python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ns = "{http://schemas.android.com/apk/res/android}"
app = root.find("application")
assert app is not None
activities = [item for item in app.findall("activity")
              if item.get(ns + "name") == "roro.stellar.manager.adb.AdbPairingActivity"]
assert len(activities) == 1, "ADB pairing activity must be registered exactly once"
assert activities[0].get(ns + "exported") == "false", "ADB pairing UI must not be externally launchable"
permissions = {item.get(ns + "name") for item in root.findall("uses-permission")}
assert "android.permission.INTERNET" in permissions, "ADB mDNS/TLS requires network access"
assert "android.permission.ACCESS_NETWORK_STATE" in permissions, "original network state permission is missing"
print("PASS: ADB pairing activity is internal and original network permissions are declared")
PY

grep -Fq 'SERVICE_TYPE = "_adb-tls-pairing._tcp."' "$DISCOVERY" || fail "original ADB TLS pairing DNS-SD service type changed"
grep -Fq 'CONNECT_SERVICE_TYPE = "_adb-tls-connect._tcp."' "$DISCOVERY" || fail "original post-pair ADB connect DNS-SD service type is missing"
grep -Fq 'this(context, SERVICE_TYPE, listener)' "$DISCOVERY" || fail "default resolver must retain the original pairing service"
grep -Fq 'AdbPairingDiscovery(Context context, String requestedServiceType' "$DISCOVERY" || fail "mDNS resolver cannot select the post-pair connect service"
grep -Fq 'manager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD' "$DISCOVERY" || fail "NSD discovery does not use the validated requested service type"
grep -Fq 'isExpectedService(String type)' "$DISCOVERY" || fail "NSD callbacks must reject results from a different service type"
grep -Fq 'manager.resolveService(next' "$DISCOVERY" || fail "NSD service result is not resolved to an address/port"
grep -Fq 'ArrayDeque<NsdServiceInfo>' "$DISCOVERY" || fail "mDNS resolution must use a bounded-in-flight queue"
grep -Fq 'if (closed || !started || resolving || resolveQueue.isEmpty()) return;' "$DISCOVERY" || fail "NSD resolution is not serialized"
grep -Fq 'manager.stopServiceDiscovery(current)' "$DISCOVERY" || fail "mDNS listener is not stopped on close"
grep -Fq 'knownNames.contains(device.serviceName)' "$DISCOVERY" || fail "stale resolved devices can reappear after service loss"

grep -Fq 'TLSv1.3' "$CLIENT" || fail "ADB pairing TLS is not pinned to TLS 1.3"
grep -Fq 'CONNECT_TIMEOUT_MS = 10_000' "$CLIENT" || fail "ADB pairing connection timeout is missing"
grep -Fq 'READ_TIMEOUT_MS = 30_000' "$CLIENT" || fail "ADB pairing read timeout is missing"
grep -Fq 'PairingContext.create(secret)' "$CLIENT" || fail "original libadb SPAKE2 context is not used"
grep -Fq 'exchangeSpake2Messages()' "$CLIENT" || fail "SPAKE2 frame exchange is missing"
grep -Fq 'exchangePeerInfo()' "$CLIENT" || fail "encrypted PeerInfo exchange is missing"
grep -Fq 'Arrays.fill(secret, (byte) 0)' "$CLIENT" || fail "SPAKE2 secret buffer is not wiped"
! grep -Fq 'Class.forName("com.android.org.conscrypt.Conscrypt")' "$CLIENT" || fail "hidden Conscrypt reflection must not be used"
grep -Fq 'AdbTlsKeyingMaterial.export(socket)' "$CLIENT" || fail "pairing client does not use the public TLS exporter wrapper"
grep -Fq 'Build.VERSION.SDK_INT < 31' "$EXPORTER" || fail "TLS exporter must fail closed below API 31"

grep -Fq 'SERVICE_TYPE = "_adb-tls-pairing._tcp."' "$DISCOVERY" || fail "pairing mDNS service constant is not public"
grep -Fq 'new AdbPairingDiscovery(getApplicationContext()' "$PAIRING" || fail "UI does not instantiate the mDNS discovery component"
grep -Fq 'discovery.start()' "$PAIRING" || fail "explicit device discovery action is not wired"
grep -Fq 'code.matches("[0-9]{6}")' "$PAIRING" || fail "UI must validate the original six-digit pairing code"
grep -Fq 'new AdbPairingClient(target.host, target.port, code, key)' "$PAIRING" || fail "selected mDNS device is not passed to the pairing client"
grep -Fq 'client.start()' "$PAIRING" || fail "UI does not execute the TLS/SPAKE2 pairing sequence"
grep -Fq 'AdbKey.getOrCreate(getApplicationContext())' "$PAIRING" || fail "pairing UI does not use the persistent original ADB host key"
grep -Fq 'startConnectDiscovery(generation)' "$PAIRING" || fail "successful SPAKE2 pairing must continue with original ADB connect DNS-SD discovery"
grep -Fq 'AdbPairingDiscovery.CONNECT_SERVICE_TYPE' "$PAIRING" || fail "post-pair discovery does not use _adb-tls-connect._tcp"
grep -Fq 'putString("connect_service_name"' "$PAIRING" || fail "resolved ADB connect service name is not persisted"
grep -Fq 'putString("connect_host"' "$PAIRING" || fail "resolved ADB connect host is not persisted"
grep -Fq 'putInt("connect_port"' "$PAIRING" || fail "resolved ADB connect port is not persisted"
grep -Fq 'remove("connect_port")' "$PAIRING" || fail "lost ADB connect service does not clear stale endpoint state"
grep -Fq 'ADB Shell 命令通道尚未迁入' "$PAIRING" || fail "UI must not claim that endpoint discovery is an active ADB Shell session"

grep -Fq 'pairingCode.setText("")' "$PAIRING" || fail "pairing code remains in the visible input after starting"
grep -Fq 'client.close()' "$PAIRING" || fail "pairing client is not closed after the attempt"
grep -Fq 'stopDiscovery();' "$PAIRING" || fail "mDNS discovery is not stopped when the UI is destroyed"
grep -Fq 'AdbPairingActivity.class' "$SECURE" || fail "Stellar secure-settings screen has no ADB pairing entry"

# Pairing must remain separate from system permission grants: the pairing
# screen stores only its ADB peer result and never runs pm grant/revoke.
grep -Fq '"fx_stellar_adb_pairing"' "$PAIRING" || fail "ADB pairing result is not stored independently"
! grep -Fq 'RootAccess' "$PAIRING" || fail "pairing UI must not bypass the separate Root permission grant"
! grep -Fq 'pm grant' "$PAIRING" || fail "pairing UI must not execute pm grant automatically"
! grep -Fq 'runPermissionChange' "$PAIRING" || fail "pairing UI must not trigger the separate permission screen's grant action"
grep -Fq 'runPermissionChange(true)' "$SECURE" || fail "explicit secure-settings grant confirmation disappeared"
echo "PASS: native mDNS discovery, serialized resolve, TLS/SPAKE2 pairing UI, cancellation and separate permission boundary"
