#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSystemExpandActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for f in "$MAIN" "$MANIFEST" "$ACTIVITY"; do [ -s "$f" ] || fail "Dia SystemExpand migration file missing: $f"; done
python3 - "$MAIN" "$MANIFEST" "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
main, manifest_path, activity = [Path(x).read_text(encoding="utf-8") for x in sys.argv[1:]]
assert 'section("Hook 工具与调试");' in main, "Dia SystemExpand must remain inside the unified FX Hook hub"
start = main.index('addNativeActionCard("系统扩展",')
route = main[start:start + 600]
assert "FxDiaSystemExpandActivity.class" in route, "SystemExpand Hook action card must open its native Activity"
assert '"打开系统扩展"' in route, "SystemExpand must have an explicit native action label"
assert "selectedBottomTab = 4;" in main and "hookHubVisible = true;" in main, "SystemExpand entry must be reachable from the Hook primary tab"
manifest = ET.fromstring(manifest_path)
ns = "{http://schemas.android.com/apk/res/android}"
nodes = [x for x in manifest.findall("./application/activity")
         if x.attrib.get(ns + "name") == ".imported.dia.FxDiaSystemExpandActivity"]
assert len(nodes) == 1, "SystemExpand Activity must be registered exactly once"
assert nodes[0].attrib.get(ns + "exported") == "false", "SystemExpand must remain private"
for token in ('"Wi-Fi Proxy"', '"允许从未知来源安装"', '"重启 Package Installer"',
              '"ro.debuggable / 调试目标"', "Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES",
              "REQUEST_INSTALL_PACKAGES", "FxDiaWifiProxyActivity.class"):
    assert token in activity, f"SystemExpand real behavior missing: {token}"
assert "先检查 Android 全部安装会话" in activity, "SystemExpand must explain the installer-session preflight"
for token in ("getAllSessions()", "FxDiaInstallerRestartPolicy.isSafeToRestart(", "confirmPackageInstallerRestart(packageName)", 'RootAccess.execute(\n                        "am force-stop " + packageName'):
    assert token in activity, f"SystemExpand installer-session/confirmed restart guard missing: {token}"
assert "不会伪装成已启用的调试 Hook" in activity, "unsupported framework hook must not be presented as operational"
for token in (
    'STATE_SCROLL_Y = "fx_dia_system_expand_scroll_y"',
    "private ScrollView systemExpandScroll;",
    "state.getInt(STATE_SCROLL_Y, 0)",
    "systemExpandScroll = scroll;",
    "outState.putInt(STATE_SCROLL_Y",
    "systemExpandScroll == scroll && scroll.getParent() != null",
    "scroll.scrollTo(0, restoreY);"):
    assert token in activity, f"SystemExpand page state restoration missing: {token}"
print("PASS: Dia SystemExpand native screen is reachable from the unified Hook hub and restores its scroll position safely")
PY
