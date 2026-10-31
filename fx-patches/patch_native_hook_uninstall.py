#!/usr/bin/env python3
"""Fix uninstall warning helper ordering and point installer guidance at native Hook UI."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
uninstall = root / "uninstall.sh"
customize = root / "customize.sh"
if not uninstall.is_file() or not customize.is_file():
    raise SystemExit("FX uninstall.sh or customize.sh is missing")

source = uninstall.read_text(encoding="utf-8")
helper = '''_mitm_warn() {
  _msg="PrivacyGuard uninstall warning: $*"
  echo "$_msg" >&2
  if command -v log >/dev/null 2>&1; then log -p w -t PrivacyGuardUninstall "$_msg" 2>/dev/null; fi
}
'''
if source.count(helper) != 1:
    raise SystemExit("uninstall warning helper does not match the reviewed source")
source = source.replace(helper, "", 1)
anchor = "PG_CLEANUP_INCOMPLETE=0\n"
if source.count(anchor) != 1:
    raise SystemExit("uninstall initialization anchor changed; refusing to move helper")
source = source.replace(anchor, anchor + helper, 1)
first_call = source.find('_mitm_warn "scheduler PID')
definition = source.find("_mitm_warn() {")
if first_call < 0 or definition < 0 or definition > first_call:
    raise SystemExit("uninstall warning helper is not defined before the scheduler cleanup path")
uninstall.write_text(source, encoding="utf-8")

ui = customize.read_text(encoding="utf-8")
replacements = {
    'ui_print "    Hook 应用推荐列表位于 FX WebUI「Hook 目标应用」管理界面。"':
        'ui_print "    Hook 应用列表与按应用配置位于 FX Hook 原生 App 的 Hook 标签页。"',
    'ui_print "  [✓] FXAdHook APK 安装/检查完成（这不是 LSPosed 框架本身）"':
        'ui_print "  [✓] FX Hook APK 安装/检查完成（这不是 LSPosed 框架本身）"',
    'ui_print "  [i] 检测到 LSPosed 目录；仍需在管理器启用 FX Ad Hook 并选择相同作用域。"':
        'ui_print "  [i] 检测到 LSPosed 目录；仍需在管理器启用 FX 并选择相同作用域。"',
}
for old, new in replacements.items():
    if old in ui:
        ui = ui.replace(old, new, 1)
    elif new not in ui:
        raise SystemExit("customize.sh UI guidance anchor changed: " + old)
if "FX WebUI「Hook 目标应用」" in ui or "FXAdHook APK" in ui or "FX Ad Hook" in ui:
    raise SystemExit("installer still advertises the retired WebUI/split Hook entry")
customize.write_text(ui, encoding="utf-8")
print("Moved uninstall warning helper before first use and updated installer guidance to native FX Hook UI.")
