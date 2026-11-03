#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RECEIVER="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
[ -s "$RECEIVER" ] || { echo "FAIL: Tasker receiver is missing" >&2; exit 1; }
python3 - "$RECEIVER" "$MANIFEST" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

receiver_path, manifest_path = map(Path, sys.argv[1:])
source = receiver_path.read_text(encoding="utf-8")
root = receiver_path.parents[0]
widget_source = (root / "FxYulongAdWidgetProvider.java").read_text(encoding="utf-8")
tile_source = (root / "FxYulongAdTileService.java").read_text(encoding="utf-8")
ad_activity = (root / "FxYulongAdActivity.java").read_text(encoding="utf-8")
general_activity = (root / "FxYulongAdGeneralActivity.java").read_text(encoding="utf-8")
gate_source = (root / "FxYulongAdOperationGate.java").read_text(encoding="utf-8")
gate_source = (root / "FxYulongAdOperationGate.java").read_text(encoding="utf-8")
manifest = ET.parse(manifest_path).getroot()
ns = "{http://schemas.android.com/apk/res/android}"

assert "AtomicBoolean REQUEST_PENDING" in source, "exported receiver needs a process-wide in-flight guard"
assert "REQUEST_PENDING.compareAndSet(false,true)" in source, "Root action must be accepted atomically"
assert "publishResult(context,action,enabled,false,75)" in source, "duplicate requests must receive a busy result"
assert source.count('new Thread(()->{') == 1, "only the guarded request may create a worker"
assert "REQUEST_PENDING.set(false);" in source, "in-flight guard must be released"
assert "pending.finish();" in source, "goAsync result must always be finished"
assert "private static void publishResult" in source, "result reporting must be centralized"
assert "reply.setPackage(context.getPackageName())" in source, "result broadcasts must be scoped to the FX package"
assert "RootAccess.execute(command,90000L,128*1024)" in source, "Tasker must still use the fixed allowlisted Root command"

# All three UI/automation entry points must serialize writes through one process gate.
assert "AtomicLong NEXT_TOKEN" in gate_source
assert "AtomicLong OWNER_TOKEN" in gate_source
assert "OWNER_TOKEN.compareAndSet(0L, token)" in gate_source
assert "OWNER_TOKEN.compareAndSet(token, 0L)" in gate_source
assert "FxYulongAdOperationGate.tryAcquire()" in source
assert source.count("FxYulongAdOperationGate.release(gateToken)") == 3, "Tasker must release gate on all three exit paths"

receiver = next((x for x in manifest.findall("./application/receiver")
                 if x.attrib.get(ns + "name", "").endswith("FxYulongAdTaskerReceiver")), None)
assert receiver is not None, "Tasker receiver is not declared"
assert receiver.attrib.get(ns + "exported") == "true", "Tasker compatibility must remain externally callable"
actions = {x.attrib.get(ns + "name") for x in receiver.findall("./intent-filter/action")}
required = {
    "de.privacyguard.adhook.AD_FILTER_ENABLE",
    "de.privacyguard.adhook.AD_FILTER_DISABLE",
    "app.pwhs.blockads.TASKER_START",
    "app.pwhs.blockads.TASKER_STOP",
}
assert required.issubset(actions), f"Tasker action aliases were lost: {sorted(required - actions)}"
assert "startForegroundService" not in source and "AdBlockVpnService" not in source,     "Tasker action must not start a competing VpnService"

# Widget refresh and toggle broadcasts share one bounded queue and cannot pile up Root work.
assert "new ArrayBlockingQueue<>(2)" in widget_source
assert "REFRESH_PENDING.compareAndSet(false, true)" in widget_source
assert "TOGGLE_PENDING.compareAndSet(false, true)" in widget_source
assert "catch (RejectedExecutionException full)" in widget_source
toggle_body = widget_source[widget_source.find("TOGGLE_PENDING.compareAndSet(false, true)"):widget_source.find("private static int readEnabled")]
worker_finally_at = toggle_body.find("} finally {")
assert worker_finally_at >= 0, "widget Root worker must have a completion finally block"
worker_finally = toggle_body[worker_finally_at:]
assert "pending.finish();" in worker_finally, "widget Root toggle must always finish its asynchronous broadcast"
assert worker_finally.find("FxYulongAdOperationGate.release(gateToken)") < worker_finally.find("TOGGLE_PENDING.set(false);") < worker_finally.find("pending.finish();"), "widget worker must release the shared gate, clear its pending flag, then finish";

assert "Executors.newSingleThreadExecutor" not in widget_source
widget = next((x for x in manifest.findall("./application/receiver")
               if x.attrib.get(ns + "name", "").endswith("FxYulongAdWidgetProvider")), None)
assert widget is not None and widget.attrib.get(ns + "exported") == "false"

# Quick Settings must not treat an unreadable Root state as disabled and turn filtering on.
assert "new ArrayBlockingQueue<>(1)" in tile_source
assert "refreshPending.compareAndSet(false, true)" in tile_source
assert "togglePending.compareAndSet(false, true)" in tile_source
assert "current == Tile.STATE_UNAVAILABLE" in tile_source
assert "未更改" in tile_source
assert "worker.shutdownNow();" in tile_source
assert "Executors.newSingleThreadExecutor" not in tile_source
assert "gateToken = FxYulongAdOperationGate.tryAcquire();" in tile_source
assert "if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);" in tile_source
assert "FxYulongAdOperationGate.tryAcquire()" in widget_source
assert widget_source.count("FxYulongAdOperationGate.release(gateToken)") == 3, "widget must release the cross-entry gate on every failure/finish path"
tile = next((x for x in manifest.findall("./application/service")
             if x.attrib.get(ns + "name", "").endswith("FxYulongAdTileService")), None)
assert tile is not None
assert tile.attrib.get(ns + "permission") == "android.permission.BIND_QUICK_SETTINGS_TILE"
assert tile.attrib.get(ns + "exported") == "true"

# All Android-side ad-master writers share one process gate; the yulong shell
# command retains its own mkdir transaction lock for cross-process callers.
assert "AtomicLong NEXT_TOKEN" in gate_source
assert "AtomicLong OWNER_TOKEN" in gate_source
assert "OWNER_TOKEN.compareAndSet(0L, token)" in gate_source
assert "OWNER_TOKEN.compareAndSet(token, 0L)" in gate_source
assert "FxYulongAdOperationGate.tryAcquire()" in source
assert "FxYulongAdOperationGate.tryAcquire()" in widget_source
assert "FxYulongAdOperationGate.tryAcquire()" in tile_source
assert "FxYulongAdOperationGate.tryAcquire()" in ad_activity
assert 'args.matches("^ad-master\\\\s+[01]$")' in ad_activity
assert "FxYulongAdOperationGate.release(gateToken);" in ad_activity
assert "FxYulongAdOperationGate.tryAcquire()" in general_activity
assert "FxYulongAdOperationGate.release(gateToken);" in general_activity
assert "finally {" in general_activity and "导入未开始" in general_activity
# Queueable Activities must acquire the global gate only after their worker starts;
# otherwise onDestroy()+shutdownNow() can drop a queued task while leaking BUSY forever.
restore_worker = general_activity.find("worker.execute(() -> {", general_activity.find("private void applyImport(JSONObject json)"))
restore_gate = general_activity.find("gateToken = FxYulongAdOperationGate.tryAcquire();", restore_worker)
restore_release = general_activity.find("if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);", restore_gate)
assert restore_worker >= 0 and restore_gate > restore_worker and restore_release > restore_gate
assert general_activity.find("FxYulongAdOperationGate.tryAcquire();", general_activity.find("private void applyImport(JSONObject json)")) >= restore_worker
ad_worker = ad_activity.find("worker.execute(()->{", ad_activity.find("private void apply(String args,String label)"))
ad_gate = ad_activity.find("gateToken=FxYulongAdOperationGate.tryAcquire();", ad_worker)
ad_release = ad_activity.find("if(gateToken!=0L)FxYulongAdOperationGate.release(gateToken);", ad_gate)
assert ad_worker >= 0 and ad_gate > ad_worker and ad_release > ad_gate
print("PASS: Tasker, widget and Quick Settings Root toggles are bounded, serialized and fail closed")
PY
