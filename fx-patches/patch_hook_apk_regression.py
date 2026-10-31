#!/usr/bin/env python3
"""Fix bundled Hook regressions for the unified dual-entry APK."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
test = root / "scripts/tests/v1.0.0-lsposed-ad-hook-apk-regression.sh"
if not test.is_file():
    raise SystemExit("FX Hook APK regression test is missing")
src = test.read_text(encoding="utf-8")
old = 'DEXSTR=$(for dex in classes.dex classes2.dex classes3.dex; do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)'
new = 'DEXSTR=$(for dex in $(unzip -Z1 "$APK" | grep -E \'^classes([0-9]+)?[.]dex$\'); do unzip -p "$APK" "$dex" 2>/dev/null | strings || true; done)'
if old in src:
    src = src.replace(old, new, 1)
elif new not in src:
    raise SystemExit("DEX scan line does not match known regression-test versions")

# Avoid SIGPIPE noise from repeatedly piping a large DEX string into grep -q.
if 'DEXSTR_FILE=$(mktemp)' not in src:
    src = src.replace(
        new,
        new + """\nDEXSTR_FILE=$(mktemp)
printf '%s\\n' "$DEXSTR" > "$DEXSTR_FILE"
trap 'rm -f "$DEXSTR_FILE"' EXIT""",
        1,
    )
old_grep = 'printf \'%s\' "$DEXSTR" | grep -q "$token" || fail "compiled hook marker missing: $token"'
new_grep = 'grep -Fq "$token" "$DEXSTR_FILE" || fail "compiled hook marker missing: $token"'
if old_grep in src:
    src = src.replace(old_grep, new_grep, 1)
elif new_grep not in src:
    raise SystemExit("DEX marker scan does not match known regression-test versions")
old_marker = '"auto member candidate hook installed="'
new_marker = '"auto member candidate hooks installed="'
if old_marker in src:
    src = src.replace(old_marker, new_marker, 1)
elif new_marker not in src:
    raise SystemExit("member candidate log marker does not match known source versions")
test.write_text(src, encoding="utf-8")

# The unified build intentionally removed the split FXAdHook artifact. Keep the
# target-scope integration test aligned with the one-APK build metadata.
scope_test = root / "scripts/tests/v1.0.0-lsposed-ad-hook-target-scope-regression.sh"
if scope_test.is_file():
    scope = scope_test.read_text(encoding="utf-8")
    scope = scope.replace("optional/FXAdHook-BUILD-INFO.txt", "optional/FXUnifiedHook-BUILD-INFO.txt")
    scope = scope.replace(
        "grep -q 'LSPosed API 101' \"$ROOT/optional/FXUnifiedHook-BUILD-INFO.txt\" || fail \"modern API provenance missing\"",
        "grep -Fq 'Dual entrypoints: legacy Xposed API 93+ and modern libxposed API 101' \"$ROOT/optional/FXUnifiedHook-BUILD-INFO.txt\" || fail \"unified Hook API provenance missing\""
    )
    if "optional/FXAdHook-BUILD-INFO.txt" in scope or "LSPosed API 101" in scope:
        raise SystemExit("target-scope regression still references obsolete split-APK metadata")
    old_ui_block = """# The UI must offer actual application selection and distinguish UID blocking.
grep -q 'id="cardFxAdHook"' "$UI" || fail "actual LSPosed UI missing"
grep -q '应用网络阻断（UID）' "$UI" || fail "legacy Hook false label not renamed"
grep -q 'id="fxHookManage"' "$UI" || fail "app picker missing"
grep -q 'if(!loaded)throw new Error' "$UI" || fail "failed app-list reads must not allow empty target save"
grep -q 'member_diag' "$UI" || fail "read-only member diagnostic UI key missing"
grep -q 'exif_strip' "$UI" || fail "EXIF privacy option missing from UI"
grep -q 'clipboard_read_block' "$UI" || fail "clipboard privacy option missing from UI"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"
# New ad module has its own diagnostic-only contract; legacy MainHook's unrelated setResult hooks are out of scope.
grep -q '会员选项仅做只读' "$UI" || fail "UI must explicitly label membership feature as read-only diagnostics"
grep -q '不伪造 VIP 状态' "$UI" || fail "UI must not advertise VIP unlock"
"""
    new_ui_block = """# LSPosed target management is native-only. Keep the unrelated UID network
# blocking controls in WebUI, but reject the retired second LSPosed editor.
APP_HOOK_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$APP_HOOK_UI" ] || fail "native FX Hook Activity source missing"
! grep -Fq 'id="cardFxAdHook"' "$UI" || fail "duplicate WebUI LSPosed card remains"
! grep -Fq 'fxHookAppList' "$UI" || fail "duplicate WebUI LSPosed app picker remains"
! grep -Fq 'fxHookManage' "$UI" || fail "duplicate WebUI LSPosed manager remains"
grep -q '应用网络阻断（UID）' "$UI" || fail "separate UID network-blocking UI was removed"
grep -Fq 'String[] labels = {"VPN", "Ad", "隐私", "脚本", "Hook", "设置"};' "$APP_HOOK_UI" || fail "native six-tab Hook navigation missing"
grep -Fq 'section("自定义 Hook")' "$APP_HOOK_UI" || fail "native per-app custom Hook editor missing"
grep -Fq '会员诊断仅记录应用内可观察状态' "$APP_HOOK_UI" || fail "native membership diagnostics must remain read-only"
grep -Fq 'toggle("清理图片/视频元数据", "exif_strip"' "$APP_HOOK_UI" || fail "native EXIF privacy option missing"
grep -Fq 'toggle("阻止剪贴板读取", "clipboard_read_block"' "$APP_HOOK_UI" || fail "native clipboard privacy option missing"
grep -Fq 'DeveloperHookRule.parse' "$APP_HOOK_UI" || fail "native custom Hook descriptor validation missing"
grep -q 'clipboard_read_block=1' "$ROOT/scripts/status.sh" || fail "clipboard privacy target missing from status accounting"
"""
    if old_ui_block in scope:
        scope = scope.replace(old_ui_block, new_ui_block, 1)
    elif new_ui_block not in scope:
        raise SystemExit("target-scope regression still requires the retired WebUI LSPosed editor")
    if 'id="cardFxAdHook"' in scope or 'id="fxHookManage"' in scope:
        raise SystemExit("target-scope regression still references obsolete WebUI Hook IDs")
    scope_test.write_text(scope, encoding="utf-8")
print("Updated unified Hook APK and native-only target-scope regression assertions.")
