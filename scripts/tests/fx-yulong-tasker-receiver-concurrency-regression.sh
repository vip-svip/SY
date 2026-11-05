#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RECEIVER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java"
WIDGET="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdWidgetProvider.java"
TILE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTileService.java"
AD="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
GENERAL="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java"
GATE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdOperationGate.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
VPN="$ROOT/scripts/yulong-vpn-control.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$RECEIVER" "$WIDGET" "$TILE" "$AD" "$GENERAL" "$GATE" "$VPN" "$MANIFEST"; do
  [ -s "$f" ] || fail "required Yulong integration source missing: $f"
done
python3 - "$RECEIVER" "$WIDGET" "$TILE" "$AD" "$GENERAL" "$GATE" "$MANIFEST" "$VPN" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

receiver_path, widget_path, tile_path, ad_path, general_path, gate_path, manifest_path, vpn_path = map(Path, sys.argv[1:])
receiver = receiver_path.read_text(encoding="utf-8")
widget = widget_path.read_text(encoding="utf-8")
widget_layout = (widget_path.parents[6] / "res/layout/fx_yulong_ad_widget.xml").read_text(encoding="utf-8")
assert 'android:text="FX VPN 快捷控制"' in widget_layout, "widget heading must match its migrated VPN function"
assert 'android:text="节点：未选择"' in widget_layout, "widget body must not retain ad-block count copy"
assert 'android:text="启动 VPN"' in widget_layout, "widget default action must match its VPN start/stop behavior"
tile = tile_path.read_text(encoding="utf-8")
ad = ad_path.read_text(encoding="utf-8")
general = general_path.read_text(encoding="utf-8")
gate = gate_path.read_text(encoding="utf-8")
vpn = vpn_path.read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
A = "{http://schemas.android.com/apk/res/android}"

# Legacy Yulong Tasker actions must control the unified VPN route, not the ad master.
# The package picker is convenience-only: it never pins or authorizes a sender by itself.
for token in (
    'button("选择已安装应用", this::chooseTaskerSenderApp)',
    'new Intent(Intent.ACTION_MAIN)',
    'launcher.addCategory(Intent.CATEGORY_LAUNCHER)',
    'queryIntentActivities(launcher, PackageManager.MATCH_DEFAULT_ONLY)',
    'FxYulongTaskerCallerPolicy.isValidPackageName(packageName)',
    'taskerSenderPackageInput.setText(packages[which])',
    'button("验证包名并固定 APK 签名", this::saveTaskerSenderPackage)',
):
    assert token in general, f"Tasker app picker/security flow missing {token}"
picker_start = general.index("private void chooseTaskerSenderApp()")
picker_end = general.index("private boolean isAutomationSenderPinned", picker_start)
picker = general[picker_start:picker_end]
assert "saveTaskerSenderPackage()" not in picker, "choosing an app must not silently pin its signer"
assert "PREF_ALLOW_EXTERNAL" not in picker, "choosing an app must not enable Root automation"

for token in (
    "LEGACY_ACTION_START.equals(action)",
    "LEGACY_ACTION_STOP.equals(action)",
    "ACTION_VPN_START.equals(action)",
    "ACTION_VPN_STOP.equals(action)",
    "yulong-vpn-control.sh",
    "yulong-ad-control.sh",
    '"target", adFilterAction ? "ad_filter" : "vpn"',
):
    assert token in receiver, f"Tasker route/action parity missing {token}"
assert 'ad-master " + enabled' in receiver, "new AD_FILTER actions must only change the ad-filter master"
assert '" /data/adb/privacyguard "' in receiver, "VPN helper must receive the canonical module and state directories"
assert "adFilterAction ? 90000L : 150000L" in receiver, "Tasker Root work must use bounded action-specific timeouts"
assert "AtomicBoolean AD_REQUEST_PENDING" in receiver
assert "AtomicBoolean VPN_REQUEST_PENDING" in receiver
assert "final AtomicBoolean requestPending" in receiver
assert "adFilterAction ? AD_REQUEST_PENDING : VPN_REQUEST_PENDING" in receiver
assert "requestPending.compareAndSet(false, true)" in receiver
assert receiver.count("requestPending.set(false)") == 4, \
    "each Tasker exit path must release the selected control-plane gate"
assert "REQUEST_PENDING.compareAndSet" not in receiver and "REQUEST_PENDING.set(" not in receiver, \
    "ad-filter and VPN Tasker actions must not share a global pending gate"
assert "FxYulongAdOperationGate.tryAcquire()" in receiver
assert receiver.count("FxYulongAdOperationGate.release(gateToken)") == 3, "ad-master transaction gate must be released on every exit path"
assert "pending.finish();" in receiver
assert "reply.setPackage(context.getPackageName())" in receiver
assert "AdBlockVpnService" not in receiver and "startForegroundService" not in receiver,     "Tasker compatibility must not start a competing VpnService"

receiver_node = next((node for node in manifest.findall("./application/receiver")
                      if node.attrib.get(A + "name", "").endswith("FxYulongAdTaskerReceiver")), None)
assert receiver_node is not None and receiver_node.attrib.get(A + "exported") == "true"
actions = {node.attrib.get(A + "name") for node in receiver_node.findall("./intent-filter/action")}
required_actions = {
    "de.privacyguard.adhook.AD_FILTER_ENABLE",
    "de.privacyguard.adhook.AD_FILTER_DISABLE",
    "de.privacyguard.adhook.VPN_START",
    "de.privacyguard.adhook.VPN_STOP",
    "app.pwhs.blockads.TASKER_START",
    "app.pwhs.blockads.TASKER_STOP",
}
assert required_actions <= actions, f"Tasker legacy/new action filters missing: {sorted(required_actions-actions)}"

# Widget is the original Yulong VPN lifecycle widget. It does not own the ad filter.
# The static default caption "启动 VPN" is asserted against widget_layout above;
# Provider refresh replaces it with the dynamic live-state labels asserted below.
for token in (
    "new ArrayBlockingQueue<>(2)",
    "REFRESH_PENDING.compareAndSet(false, true)",
    "TOGGLE_PENDING.compareAndSet(false, true)",
    "catch (RejectedExecutionException full)",
    'shell("status")',
    'shell(operation)',
    "yulong-vpn-control.sh",
    "RootAccess.execute(shell(operation)",
    "pending.finish();",
    "VPN 已启用",
    "启动防护",
    "重试启动",
    "停止 VPN",
):
    assert token in widget, f"VPN widget migration missing {token}"
assert "FxYulongAdOperationGate" not in widget, "VPN widget must not lock the separate ad-filter setting"
assert "AD_MASTER|" not in widget and "dns-log-tail" not in widget, "VPN widget must not present ad state as VPN state"
assert "worker.shutdownNow()" not in widget, "AppWidgetProvider worker is process-scoped"
assert "MainActivity.class" in widget, "widget open action must lead to the single FX app"

widget_node = next((node for node in manifest.findall("./application/receiver")
                    if node.attrib.get(A + "name", "").endswith("FxYulongAdWidgetProvider")), None)
assert widget_node is not None and widget_node.attrib.get(A + "exported") == "false"

# Ad Quick Settings tile remains the independent ad-master switch.
assert "FxYulongAdOperationGate.tryAcquire()" in tile
assert "ad-master" in tile
assert "FxYulongAdOperationGate.tryAcquire()" in ad
assert "FxYulongAdOperationGate.tryAcquire()" in general
for token in ("AtomicLong NEXT_TOKEN", "AtomicLong OWNER_TOKEN",
              "OWNER_TOKEN.compareAndSet(0L, token)", "OWNER_TOKEN.compareAndSet(token, 0L)"):
    assert token in gate

# No migrated Tasker/widget class may start a second VPN service.
vpn_services = [node.attrib.get(A + "name", "") for node in manifest.findall("./application/service")
                if node.attrib.get(A + "permission") == "android.permission.BIND_VPN_SERVICE"]
assert len(vpn_services) <= 1, f"multiple competing VpnService components: {vpn_services}"

# Controller contract is tested separately by the hermetic shell regression.
for token in ('export MP PG', 'pg_get vpn_node', 'pg_set vpn_mode', 'scripts/status.sh',
              'scripts/apply.sh', 'VPN_START_APPLY_FAILED', 'VPN_STOP_APPLY_FAILED',
              'VPN_NO_NODE_SELECTED'):
    assert token in vpn, f"canonical VPN lifecycle helper missing {token}"

# A successful control command and a persisted receipt are separate outcomes.
for token in (
    "boolean receiptPersisted = false;",
    ".commit();",
    'reply.putExtra("receipt_persisted", receiptPersisted)',
):
    assert token in receiver, f"receipt persistence signal missing: {token}"
assert 'getBooleanExtra("receipt_persisted", true)' in general, \
    "General UI must retain backward compatibility with older receivers"
assert "收到本次实时命令回执，但未能保存到本地历史" in general, \
    "General UI must expose a live result when history commit fails"
assert "boundedTaskerText" in general, "live receipt details must be size bounded"

print("PASS: Yulong Tasker aliases and home widget control one FX VPN route; ad master remains independent")
PY
