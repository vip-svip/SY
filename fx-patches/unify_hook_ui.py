#!/usr/bin/env python3
"""Consolidate all LSPosed Hook controls into one FX WebUI management card."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
page = root / "webroot/index.html"
html = page.read_text(encoding="utf-8")
html = html.replace(
    "还必须在 LSPosed 中启用 PrivacyGuardHook，并将目标 APP 加入 Scope。",
    "还必须在 LSPosed 中启用 FX Hook 模块，并将目标 APP 加入作用域。"
)

legacy_marker = '<div class="card" id="privacyHookMasterCard">'
modern_marker = '<div class="card fxah-card" id="cardFxAdHook">'


def div_block(source: str, marker: str):
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"Hook UI block missing: {marker}")
    depth = 0
    for match in re.finditer(r"<div\\b[^>]*>|</div>", source[start:]):
        token = match.group(0)
        if token.startswith("</div"):
            depth -= 1
            if depth == 0:
                return start, start + match.end(), source[start:start + match.end()]
        else:
            depth += 1
    raise SystemExit(f"Unbalanced Hook UI div: {marker}")


# Idempotent when the source archive already contains the consolidated layout.
if legacy_marker not in html:
    pos = html.find(modern_marker)
    privacy = html.find('id="pagePrivacy"')
    scripts = html.find('id="pageScript"')
    if pos >= 0 and privacy >= 0 and privacy < pos < scripts and html.count(modern_marker) == 1:
        page.write_text(html, encoding="utf-8")
        print("PASS: unified LSPosed Hook UI already present")
        raise SystemExit(0)
    raise SystemExit("neither legacy nor valid unified Hook UI layout found")

legacy_start, legacy_end, legacy_card = div_block(html, legacy_marker)
modern_start, modern_end, modern_card = div_block(html, modern_marker)

legacy_button_match = re.search(r'<button class="setrow">.*?</button>', legacy_card, re.S)
if not legacy_button_match:
    raise SystemExit("legacy LSPosed master switch missing")
legacy_button = legacy_button_match.group(0)

old_heading = '<span class="ct">应用内 Hook（LSPosed）</span>'
new_heading = '<span class="ct">统一应用内 Hook 管理</span>'
if old_heading not in modern_card:
    raise SystemExit("modern Hook card heading missing")
modern_card = modern_card.replace(old_heading, new_heading, 1)
old_header = (
    '<div class="cardhead"><span class="ct">统一应用内 Hook 管理</span>'
    '<span class="badge auto" id="fxHookBadge">独立作用域</span></div>'
)
new_header = (
    '<div class="cardhead"><span class="ct">统一应用内 Hook 管理</span>'
    '<span class="badge auto" id="fxHookBadge">统一配置</span></div>'
    '<div class="sp-sec">隐私保护、广告过滤、传感器、通知、剪贴板和目标应用均在此管理；'
    '下方详细选项共用 FX 配置并统一同步。无需分别打开两个 Hook 界面。</div>'
    + legacy_button
)
if old_header not in modern_card:
    raise SystemExit("modern Hook card header structure changed unexpectedly")
modern_card = modern_card.replace(old_header, new_header, 1)
for token in ('data-key="lsposed_enabled"', 'id="fxHookMaster"',
              'id="fxHookPrivacyMaster"', 'id="fxHookManage"', 'id="fxHookSync"'):
    if token not in modern_card:
        raise SystemExit(f"unified Hook card missing control: {token}")

# Remove the later Script-page card first, then replace the Privacy-page card.
html = html[:modern_start] + html[modern_end:]
legacy_start2, legacy_end2, _ = div_block(html, legacy_marker)
html = html[:legacy_start2] + modern_card + html[legacy_end2:]

if html.count(modern_marker) != 1 or legacy_marker in html:
    raise SystemExit("duplicate or stale Hook UI containers remain")
privacy = html.find('id="pagePrivacy"')
scripts = html.find('id="pageScript"')
card = html.find(modern_marker)
if not (privacy >= 0 and privacy < card < scripts):
    raise SystemExit("unified Hook management card is not on the Privacy page")

page.write_text(html, encoding="utf-8")
print("PASS: all LSPosed Hook master controls and target management now share one FX Privacy UI card")
