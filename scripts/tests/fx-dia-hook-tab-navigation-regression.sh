#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$MAIN" ] || { echo "FAIL: FX MainActivity source missing" >&2; exit 1; }
python3 - "$MAIN" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text(encoding="utf-8")
assert 'case "方法 Hook": case "函数重写":' in s
assert 'case "规则组": case "规则列表":' in s
for anchor in ('case "方法 Hook": case "函数重写":',
               'case "规则组": case "规则列表":'):
    start = s.index(anchor)
    route = s[start:start + 500]
    assert 'showAppList("自定义 Hook")' in route, f"{anchor}: Dia Hook route must use its custom Hook app list"
assert 'boolean hookToolsPage = "自定义 Hook".equals(activePrivacySection);' in s
assert 'selectedBottomTab = activePrivacySection == null || hookToolsPage ? 4 : 2;' in s, "Dia custom Hook app picker must select Hook tab index 4, not Privacy tab index 2"
assert 'back.setText("自定义 Hook".equals(activePrivacySection) ? "返回 Hook 应用列表"' in s, "Dia custom Hook target must have a Hook-specific return label"
assert 'back.setText(activePrivacySection == null ? "返回应用列表" : "返回隐私应用列表");' not in s, "old incorrect privacy return label remains"
print("PASS: Dia custom Hook app picker and target remain under FX Hook tab with Hook-specific return navigation")
PY
