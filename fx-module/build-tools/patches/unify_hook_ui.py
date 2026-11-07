#!/usr/bin/env python3
"""Consolidate all LSPosed Hook controls into one FX WebUI management card.

The FX WebUI source shipped by the app repository already carries the modern
``cardFxAdHook`` container, while archives restored from older releases can
still carry the retired ``privacyHookMasterCard``.  Both shapes must end up as
one normalized card on the Privacy page, so this patcher

* folds a legacy master switch into the modern card when one is still present,
* normalizes the card header, description and module wording idempotently,
* relocates the card onto the Privacy page when a source ships it on the
  Script page,
* and fails closed when the resulting layout does not satisfy the unified
  contract.

Binding a switch to a config key that the Hook payload parser does not accept
would produce a dead control, so only the two real master keys
(``hook_ads_enabled`` and ``hook_privacy_enabled``) are required here.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
page = root / "webroot/index.html"
html = page.read_text(encoding="utf-8")

legacy_marker = '<div class="card" id="privacyHookMasterCard">'
modern_marker = '<div class="card fxah-card" id="cardFxAdHook">'

HOOK_HEADING_OLD = "应用内 Hook（LSPosed）"
HOOK_HEADING_NEW = "统一应用内 Hook 管理"
HOOK_BADGE_OLD = ">独立作用域<"
HOOK_BADGE_NEW = ">统一配置<"
HOOK_DESCRIPTOR = (
    '<div class="sp-sec">隐私保护、广告过滤、传感器、通知、剪贴板和目标应用均在此管理；'
    '下方详细选项共用 FX 配置并统一同步。无需分别打开两个 Hook 界面。</div>'
)
HOOK_REQUIRED_TOKENS = (
    'id="fxHookMaster"',
    'data-key="hook_ads_enabled"',
    'id="fxHookPrivacyMaster"',
    'data-key="hook_privacy_enabled"',
    'id="fxHookManage"',
    'id="fxHookSync"',
)


def div_block(source: str, marker: str, start_hint: int = 0):
    start = source.find(marker, start_hint)
    if start < 0:
        raise SystemExit(f"Hook UI block missing: {marker}")
    depth = 0
    for match in re.finditer(r"<div\b[^>]*>|</div>", source[start:]):
        token = match.group(0)
        if token.startswith("</div"):
            depth -= 1
            if depth == 0:
                return start, start + match.end(), source[start:start + match.end()]
        else:
            depth += 1
    raise SystemExit(f"Unbalanced Hook UI div: {marker}")


def remove_block(source: str, marker: str) -> str:
    start, end, _ = div_block(source, marker)
    while start > 0 and source[start - 1] == "\n":
        start -= 1
    return source[:start] + source[end:]


def fold_legacy_card(source: str) -> str:
    """Fold the retired master card into the modern card, then drop the copy."""
    if legacy_marker not in source:
        return source
    _, _, legacy_card = div_block(source, legacy_marker)
    legacy_button_match = re.search(r'<button class="setrow">.*?</button>', legacy_card, re.S)
    if not legacy_button_match:
        raise SystemExit("legacy LSPosed master switch missing")
    legacy_button = legacy_button_match.group(0)
    source = remove_block(source, legacy_marker)
    if modern_marker not in source:
        return source
    modern_start, modern_end, modern_card = div_block(source, modern_marker)
    head = modern_card.find('class="cardhead"')
    if head < 0:
        raise SystemExit("modern Hook card header structure changed unexpectedly")
    head_end = modern_card.find("</div>", head)
    if head_end < 0:
        raise SystemExit("modern Hook card header is unbalanced")
    head_end += len("</div>")
    modern_card = modern_card[:head_end] + legacy_button + modern_card[head_end:]
    return source[:modern_start] + modern_card + source[modern_end:]


def normalize_card(card: str) -> str:
    card = card.replace(HOOK_HEADING_OLD, HOOK_HEADING_NEW, 1)
    card = card.replace(HOOK_BADGE_OLD, HOOK_BADGE_NEW, 1)
    if HOOK_DESCRIPTOR not in card:
        head = card.find('class="cardhead"')
        if head < 0:
            raise SystemExit("modern Hook card header missing")
        head_end = card.find("</div>", head)
        if head_end < 0:
            raise SystemExit("modern Hook card header is unbalanced")
        head_end += len("</div>")
        card = card[:head_end] + HOOK_DESCRIPTOR + card[head_end:]
    return card


def relocate_to_privacy_page(source: str) -> str:
    privacy = source.find('id="pagePrivacy"')
    scripts = source.find('id="pageScript"')
    if privacy < 0 or scripts < 0:
        raise SystemExit("Hook UI pages are missing; refusing to guess the page layout")
    if privacy < source.find(modern_marker) < scripts:
        return source
    _, _, card = div_block(source, modern_marker)
    source = remove_block(source, modern_marker)
    scripts = source.find('id="pageScript"')
    close = source.rfind("</div>", 0, scripts)
    if close < 0:
        raise SystemExit("Privacy page container is unbalanced")
    return source[:close] + card + "\n" + source[close:]


def retired_app_wording(source: str) -> str:
    source = source.replace(
        "还必须在 LSPosed 中启用 PrivacyGuardHook，并将目标 APP 加入 Scope。",
        "还必须在 LSPosed 中启用 FX Hook 模块，并将目标 APP 加入作用域。",
    )
    source = source.replace(
        "随后请在 LSPosed 中启用 FXhook、确认目标 Scope",
        "随后请在 LSPosed 中启用 FX Hook 模块、确认目标作用域",
    )
    source = source.replace(
        "安装器在 FXhook 新 APK 安装成功后会卸载旧 PrivacyGuardHook 应用包",
        "安装器在 FXhook 新 APK 安装成功后会卸载旧版隐私 Hook 应用包",
    )
    return source


html = fold_legacy_card(html)
if html.count(modern_marker) != 1:
    raise SystemExit("duplicate or missing unified Hook UI containers remain")
start, end, card = div_block(html, modern_marker)
html = html[:start] + normalize_card(card) + html[end:]
html = relocate_to_privacy_page(html)
html = retired_app_wording(html)

privacy = html.find('id="pagePrivacy"')
scripts = html.find('id="pageScript"')
card_pos = html.find(modern_marker)
if not (privacy >= 0 and privacy < card_pos < scripts):
    raise SystemExit("unified Hook management card is not on the Privacy page")
if legacy_marker in html:
    raise SystemExit("duplicate or stale Hook UI containers remain")
if html.count(modern_marker) != 1:
    raise SystemExit("duplicate unified Hook UI containers remain")
if HOOK_HEADING_NEW not in html:
    raise SystemExit("unified Hook card heading was not normalized")
for token in HOOK_REQUIRED_TOKENS:
    if html.count(token) != 1:
        raise SystemExit(f"unified Hook card missing control: {token}")
if "PrivacyGuardHook" in html:
    raise SystemExit("retired PrivacyGuardHook wording still present")

page.write_text(html, encoding="utf-8")
print("PASS: all LSPosed Hook master controls and target management now share one FX Privacy UI card")
