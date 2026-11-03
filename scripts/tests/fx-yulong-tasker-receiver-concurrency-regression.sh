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
manifest = ET.parse(manifest_path).getroot()
ns = "{http://schemas.android.com/apk/res/android}"

assert "AtomicBoolean REQUEST_PENDING" in source, "exported receiver needs a process-wide in-flight guard"
assert "REQUEST_PENDING.compareAndSet(false,true)" in source, "Root action must be accepted atomically"
assert "publishResult(context,action,enabled,false,75)" in source, "duplicate requests must receive a busy result"
assert source.count('new Thread(()->{') == 1, "only the guarded request may create a worker"
assert "REQUEST_PENDING.set(false);" in source, "in-flight guard must be released"
assert "pending.finish();" in source, "goAsync result must always be finished"
assert "private static void publishResult" in source, "result reporting must be centralized"
assert "RootAccess.execute(command,90000L,128*1024)" in source, "Tasker must still use the fixed allowlisted Root command"

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
assert "finally {\n                    TOGGLE_PENDING.set(false);\n                    pending.finish();" in widget_source
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
tile = next((x for x in manifest.findall("./application/service")
             if x.attrib.get(ns + "name", "").endswith("FxYulongAdTileService")), None)
assert tile is not None
assert tile.attrib.get(ns + "permission") == "android.permission.BIND_QUICK_SETTINGS_TILE"
assert tile.attrib.get(ns + "exported") == "true"
print("PASS: Tasker, widget and Quick Settings Root toggles are bounded, serialized and fail closed")
PY
