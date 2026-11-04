#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
[ -s "$MAIN" ] && [ -s "$ACTIVITY" ] || { echo "FAIL: Dia source files missing" >&2; exit 1; }
python3 - "$MAIN" "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
main = Path(sys.argv[1]).read_text(encoding="utf-8")
frida = Path(sys.argv[2]).read_text(encoding="utf-8")
route_start = main.index('case "运行日志":')
route = main[route_start:route_start + 500]
if "FxDiaFridaActivity.class" not in route or '.putExtra("dia_page", page)' not in route:
    raise SystemExit("FAIL: Dia run-log page must open the Frida target-session log screen")
if "showNativeRuntimeLogs()" in route:
    raise SystemExit("FAIL: Dia run-log page is incorrectly routed to the FX module log viewer")
checks = {
    "persist selected debug package": '.putString("target_package", targetPackage)' in frida,
    "persist selected target label": '.putString("target_name", targetName)' in frida,
    "restore target without Activity Bundle": 'prefs.getString("target_package", null)' in frida,
    "validate persisted target before reuse": 'ApplicationInfo.FLAG_DEBUGGABLE' in frida and 'ApplicationInfo.FLAG_SYSTEM' in frida,
    "clear stale target selection": 'remove("target_package").remove("target_name")' in frida,
    "restore target even on a fresh page launch": 'restoreTransientState(state);' in frida,
    "run log page opens target log": 'body.post(() -> {\n                if (targetPackage == null) chooseTarget();\n                else showSessionLog();\n            });' in frida,
    "script editor page opens full-screen editor": 'else if ("脚本编辑器".equals(title)) {\n            body.post(this::openFullScreenCodeEditor);' in frida,
}
for label, ok in checks.items():
    if not ok:
        raise SystemExit(f"FAIL: {label}")
print("PASS: Dia Frida pages retain a validated debug target and open the correct script/log tools")
PY
