#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
PROVIDER="$APP/java/de/privacyguard/adhook/imported/ad/FxYulongAdWidgetProvider.java"
MAIN="$APP/java/de/privacyguard/adhook/MainActivity.java"
AD="$APP/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
MANIFEST="$APP/AndroidManifest.xml"
LAYOUT="$APP/res/layout/fx_yulong_ad_widget.xml"
INFO="$APP/res/xml/fx_yulong_ad_widget_info.xml"
CONTROL="$ROOT/scripts/yulong-vpn-control.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$PROVIDER" "$MAIN" "$AD" "$MANIFEST" "$LAYOUT" "$INFO" "$CONTROL"; do
  [ -s "$file" ] || fail "migrated Yulong widget source missing: $file"
done
python3 - "$PROVIDER" "$MAIN" "$AD" "$MANIFEST" "$LAYOUT" "$INFO" "$CONTROL" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

provider, main, ad, manifest, layout, info, control = [
    Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]
]
root = ET.fromstring(manifest)
ns = "{http://schemas.android.com/apk/res/android}"
widgets = [n for n in root.findall("./application/receiver")
           if n.attrib.get(ns + "name", "").endswith("FxYulongAdWidgetProvider")]
assert len(widgets) == 1, "Yulong AppWidgetProvider must be registered exactly once"
widget = widgets[0]
assert widget.attrib.get(ns + "exported") == "false", "widget provider must not expose arbitrary external toggles"
actions = [a.attrib.get(ns + "name") for a in widget.findall("./intent-filter/action")]
assert "android.appwidget.action.APPWIDGET_UPDATE" in actions
metadata = next((n for n in widget.findall("./meta-data")
                 if n.attrib.get(ns + "name") == "android.appwidget.provider"), None)
assert metadata is not None and metadata.attrib.get(ns + "resource") == "@xml/fx_yulong_ad_widget_info"
widget_info = ET.fromstring(info)
assert widget_info.attrib.get(ns + "initialLayout") == "@layout/fx_yulong_ad_widget"
assert widget_info.attrib.get(ns + "updatePeriodMillis") == "1800000"

for token in (
    'ACTION_TOGGLE = "app.pwhs.blockads.widget.TOGGLE_VPN"',
    'yulong-vpn-control.sh',
    'RootAccess.execute(shell("status")',
    'json.optBoolean("vpn_on", false)',
    'json.optString("vpn_mode", "direct")',
    'json.optString("vpn_node", "")',
    'new ArrayBlockingQueue<>(2)',
    'new ThreadPoolExecutor.AbortPolicy()',
    'goAsync()',
    'pending.finish()',
    'PendingIntent.FLAG_IMMUTABLE',
    'manager.updateAppWidget(ids, views)',
):
    assert token in provider, f"widget state/toggle behavior missing: {token}"
assert "AdBlockVpnService" not in provider and "RootProxyService" not in provider,     "widget must not start a second AdBlockVpnService/RootProxyService"
assert 'FxYulongAdWidgetProvider.refreshAll(this)' in main,     "native VPN actions must refresh widget status after their real backend result"
assert 'FxYulongAdWidgetProvider.refreshAll(this)' in ad,     "Ad master configuration changes must refresh widget state"
for view_id in ("fx_yulong_widget_status", "fx_yulong_widget_count",
                "fx_yulong_widget_toggle", "fx_yulong_widget_open"):
    assert view_id in layout, f"widget layout element missing: {view_id}"

assert 'status_json()' in control and 'start_vpn()' in control and 'stop_vpn()' in control
assert 'VPN_NO_NODE_SELECTED' in control and 'VPN_START_NOT_CONFIRMED' in control
assert 'restore_mode "$old_mode"' in control, "failed starts/stops must roll back the prior mode"
assert 'case "$CMD" in' in control and 'status) status_json' in control
assert 'start) start_vpn' in control and 'stop) stop_vpn' in control
print("PASS: Yulong home-screen widget uses the single FX VPN route, reports live state, and refreshes after VPN actions")
PY
