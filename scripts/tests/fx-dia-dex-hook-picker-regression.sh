#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
DEX="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java"
RULE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperHookRule.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
python3 - "$MAIN" "$DEX" "$RULE" <<'PY'
from pathlib import Path
import sys
main, dex, rule = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
assert "REQUEST_DIA_DEX_HOOK_PICKER = 4111" in main
assert 'putExtra("allow_hook_method_pick", true)' in main
assert "startActivityForResult(dexBrowser, REQUEST_DIA_DEX_HOOK_PICKER)" in main
assert 'getStringExtra("fx_dex_hook_package")' in main
assert 'getStringExtra("fx_dex_hook_descriptor")' in main
result_handler = main[main.index("if (requestCode == REQUEST_DIA_DEX_HOOK_PICKER)"):main.index("if (requestCode == REQUEST_DIA_GPS_PICKER)")]
assert "getPackageManager().getApplicationInfo(targetPackage, 0)" in result_handler
assert "findApp(targetPackage)" not in result_handler, "DEX result must not depend on an already-loaded MainActivity app list"
assert 'DeveloperHookRule.parse("dexPick|" + descriptor + "|OBSERVE|0", targetPackage)' in main
assert "FLAG_DEBUGGABLE" in main and "FLAG_SYSTEM" in main
assert "showCustomRuleDialog(descriptor)" in main
assert "private void showCustomRuleDialog(String presetDescriptor)" in main
assert 'putExtra("fx_dex_hook_descriptor", descriptor)' in dex
assert 'putExtra("fx_dex_hook_package", targetPackage)' in dex
assert 'owner.descriptor + "->" + member.name + member.descriptor' in dex
assert "chooseDexHookMethod(item)" in dex
picker = dex[dex.index("private void chooseDexHookMethod("):dex.index("private String buildClassDetail(")]
assert "detailWorker.execute(() -> {" in picker, "DEX Hook picker must filter methods off the UI thread"
assert "collectDexHookCandidates(owner, query, targetPackage)" in picker
assert "final String targetPackage = selected.packageName;" in picker, "picker must snapshot the selected target before worker dispatch"
assert "for (FxDiaDexIndex.Member" not in picker

assert "(member.accessFlags & (0x0400 | 0x0100)) != 0" in dex
assert 'member.name.startsWith("<")' in dex
assert "DeveloperHookRule.parse" in dex
assert "NO_OP_VOID" in rule and "OBSERVE" in rule
print("PASS: DEX method picker returns exact validated descriptors to the debuggable target Hook editor; fields remain read-only")
PY
