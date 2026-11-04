#!/usr/bin/env python3
"""Ensure restored native Hook UI keeps LSPosed Manager approval authority visible."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
main = root / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
if not main.is_file():
    raise SystemExit(f"native Hook Activity is missing: {main}")
source = main.read_text(encoding="utf-8")
notice = "LSPosed 模块启用和目标应用作用域必须在 LSPosed Manager 中单独设置"

hub_start = source.find("private void showHookHub()")
hub_end = source.find("private void addModeOption", hub_start)
if hub_start < 0 or hub_end < 0:
    raise SystemExit("cannot locate native Hook hub section")
hub = source[hub_start:hub_end]
if notice not in hub:
    anchor = '        section("LSPosed");\n        TextView ls = new TextView(this);'
    if anchor in hub:
        replacement = '''        section("LSPosed");
        TextView managerNotice = new TextView(this);
        managerNotice.setText("LSPosed 模块启用和目标应用作用域必须在 LSPosed Manager 中单独设置；FX 只提交申请并读取审批结果，不会绕过 Manager 自动注入。");
        managerNotice.setTextColor(0xff697681);
        managerNotice.setPadding(dp(18), dp(6), dp(18), dp(10));
        content.addView(managerNotice);
        TextView ls = new TextView(this);'''
        hub = hub.replace(anchor, replacement, 1)
    else:
        raise SystemExit("Hook hub LSPosed section anchor changed; refusing to patch unrelated UI")
    source = source[:hub_start] + hub + source[hub_end:]

if notice not in source:
    raise SystemExit("LSPosed Manager authority notice was not written into native Hook UI")
if source.count(notice) > 3:
    raise SystemExit("duplicate LSPosed Manager authority notices detected")
main.write_text(source, encoding="utf-8")
print(f"PASS: LSPosed Manager authority notice visible in Hook hub ({main})")
