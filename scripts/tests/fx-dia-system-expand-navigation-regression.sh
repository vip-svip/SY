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
assert '{"应用与模块", "应用选择", "目标应用", "模块配置", "模块功能", "系统扩展", "Activity 入口与禁用", "隐藏应用"}' in main,     "Dia native migration menu must expose SystemExpand under application/module tools"
start = main.index('case "系统扩展":')
route = main[start:start + 300]
assert "FxDiaSystemExpandActivity.class" in route, "SystemExpand menu item must open its native Activity"
assert 'case "系统扩展":' in route and "return;" in route
manifest = ET.parse(manifest_path).getroot()
ns = "{http://schemas.android.com/apk/res/android}"
nodes = [x for x in manifest.findall("./application/activity")
         if x.attrib.get(ns + "name") == ".imported.dia.FxDiaSystemExpandActivity"]
assert len(nodes) == 1, "SystemExpand Activity must be registered exactly once"
assert nodes[0].attrib.get(ns + "exported") == "false", "SystemExpand must remain private"
for token in ('"Wi-Fi Proxy"', '"允许从未知来源安装"', '"重启 Package Installer"',
              '"ro.debuggable / 调试目标"', "Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES",
              "REQUEST_INSTALL_PACKAGES", "FxDiaWifiProxyActivity.class"):
    assert token in activity, f"SystemExpand real behavior missing: {token}"
assert "不会强制停止或重启系统安装器" in activity, "SystemExpand must preserve installer-session safety"
assert "不会伪装成已启用的调试 Hook" in activity, "unsupported framework hook must not be presented as operational"
print("PASS: Dia SystemExpand native screen is reachable from the correct four-level menu and retains truthful system actions")
PY
