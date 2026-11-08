#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
DEX="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java"
[ -s "$MAIN" ] || { echo "FAIL: FX MainActivity source missing" >&2; exit 1; }
[ -s "$DEX" ] || { echo "FAIL: Dia DEX browser source missing" >&2; exit 1; }
python3 - "$MAIN" "$DEX" <<'PY'
from pathlib import Path
import sys
main = Path(sys.argv[1]).read_text(encoding="utf-8")
dex = Path(sys.argv[2]).read_text(encoding="utf-8")

# Current native Dia entry is a DEX method picker, not the retired
# "方法 Hook/函数重写" legacy menu.
assert 'addNativeActionCard("DEX 类与方法浏览"' in main
assert 'dexBrowser.putExtra("allow_hook_method_pick", true);' in main
assert 'startActivityForResult(dexBrowser, REQUEST_DIA_DEX_HOOK_PICKER);' in main
assert 'if (requestCode == REQUEST_DIA_DEX_HOOK_PICKER)' in main
assert 'pendingDiaDexHookPicker = false;' in main
assert 'DeveloperHookRule.parse("dexPick|" + descriptor + "|OBSERVE|0", targetPackage)' in main
assert 'activePrivacySection = "自定义 Hook";' in main
assert 'showTarget(targetInfo);' in main and 'showCustomRuleDialog(descriptor);' in main

# Only debuggable user apps can return a concrete method descriptor.
assert 'getIntent().getBooleanExtra("allow_hook_method_pick", false)' in dex
assert '(selected.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0' in dex
assert '(selected.flags & (ApplicationInfo.FLAG_SYSTEM' in dex
assert 'result.putExtra("fx_dex_hook_package", targetPackage);' in dex
assert 'result.putExtra("fx_dex_hook_descriptor", descriptor);' in dex
assert 'setResult(RESULT_OK, result);' in dex

# The app picker and target remain on the FX Hook tab, with a dedicated return.
assert 'boolean hookToolsPage = "自定义 Hook".equals(activePrivacySection)' in main
assert 'selectedBottomTab = activePrivacySection == null || hookToolsPage ? 4 : 2;' in main
assert 'back.setText("自定义 Hook".equals(activePrivacySection) ? "返回 Hook 应用列表"' in main
assert 'back.setOnClickListener(v -> showAppList(activePrivacySection));' in main
assert 'showAppList("自定义 Hook");' in main
print("PASS: Dia DEX method picker returns validated user-app methods into the FX Hook tab and preserves Hook-specific navigation")
PY
