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

# The per-target editor's publish action writes FX configuration and Remote Files;
# it deliberately does not request or revoke any LSPosed scope.
publish_notice = "保存并发布 Hook 配置只更新 FX 设备端配置和 Remote Files 发布状态，不会自动授予或修改 LSPosed 作用域。目标应用作用域由 LSPosed Manager 单独管理；上方的作用域申请仍须经过 Manager 审查和批准。"
publish_anchor = "        renderCustomRules();" + chr(10) + '        Button save=new Button(this); save.setText("保存并发布 Hook 配置");'
publish_replacement = '''        renderCustomRules();
        TextView publishScopeNotice = new TextView(this);
        publishScopeNotice.setText("保存并发布 Hook 配置只更新 FX 设备端配置和 Remote Files 发布状态，不会自动授予或修改 LSPosed 作用域。目标应用作用域由 LSPosed Manager 单独管理；上方的作用域申请仍须经过 Manager 审查和批准。");
        publishScopeNotice.setTextColor(0xff697681);
        publishScopeNotice.setTextSize(12);
        publishScopeNotice.setPadding(dp(16), dp(4), dp(16), dp(10));
        content.addView(publishScopeNotice);
        Button save=new Button(this); save.setText("保存并发布 Hook 配置");'''
if publish_notice not in source:
    if source.count(publish_anchor) != 1:
        raise SystemExit("cannot locate unique Hook config publish control; refusing to patch unrelated UI")
    source = source.replace(publish_anchor, publish_replacement, 1)

if notice not in source:
    raise SystemExit("LSPosed Manager authority notice was not written into native Hook UI")
if publish_notice not in source:
    raise SystemExit("LSPosed config-publish scope notice was not written into native Hook UI")
if source.count(notice) > 3:
    raise SystemExit("duplicate LSPosed Manager authority notices detected")
main.write_text(source, encoding="utf-8")
print(f"PASS: LSPosed Manager authority and config-publish scope notices visible in native Hook UI ({main})")
