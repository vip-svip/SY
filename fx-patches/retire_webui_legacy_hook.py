#!/usr/bin/env python3
"""Remove the obsolete WebUI LSPosed manager; native FX Hook tab is authoritative."""
from pathlib import Path
import re
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: retire_webui_legacy_hook.py <webroot-index.html>")

target = Path(sys.argv[1])
if not target.is_file():
    raise SystemExit(f"WebUI file not found: {target}")
html = target.read_text(encoding="utf-8")


def remove_div_by_id(source: str, element_id: str) -> str:
    pattern = re.compile(
        r"""<div\b(?=[^>]*\bid=["']""" + re.escape(element_id)
        + r"""["'])[^>]*>""",
        re.IGNORECASE,
    )
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one <div id={element_id}>, found {len(matches)}"
        )
    start = matches[0].start()
    depth = 0
    token_pattern = re.compile(r"</?div\b[^>]*>", re.IGNORECASE)
    for token in token_pattern.finditer(source, start):
        if token.group(0).lower().startswith("</"):
            depth -= 1
        else:
            depth += 1
        if depth == 0:
            return source[:start] + source[token.end():]
    raise SystemExit(f"unbalanced <div id={element_id}>")


def remove_script_by_id(source: str, element_id: str) -> str:
    pattern = re.compile(
        r"""<script\b(?=[^>]*\bid=["']""" + re.escape(element_id)
        + r"""["'])[^>]*>.*?</script\s*>""",
        re.IGNORECASE | re.DOTALL,
    )
    result, count = pattern.subn("", source)
    if count != 1:
        raise SystemExit(
            f"expected exactly one <script id={element_id}>, found {count}"
        )
    return result


# This old controller writes a legacy schema that diverged from the native
# API-101 publisher. Retire it to avoid two competing LSPosed configuration
# surfaces. Keep the separate UID network-blocking card (#cardHook) intact.
html = remove_div_by_id(html, "cardFxAdHook")
html = remove_div_by_id(html, "fxHookDialog")
html = remove_script_by_id(html, "fx-lsposed-ad-hook-controller")

for obsolete in (
    'id="cardFxAdHook"',
    "id='cardFxAdHook'",
    'id="fxHookDialog"',
    "id='fxHookDialog'",
    'id="fx-lsposed-ad-hook-controller"',
    "id='fx-lsposed-ad-hook-controller'",
    'id="fxHookManage"',
    'id="fxHookSave"',
    'id="fxHookMaster"',
):
    if obsolete in html:
        raise SystemExit(f"obsolete WebUI Hook entry remains: {obsolete}")

if 'id="cardHook"' not in html and "id='cardHook'" not in html:
    raise SystemExit("separate UID network-blocking Hook card was unexpectedly removed")
if 'id="pageScript"' not in html or 'id="pageMore"' not in html:
    raise SystemExit("required WebUI pages missing after legacy Hook retirement")

target.write_text(html, encoding="utf-8")
print("Retired duplicate WebUI LSPosed manager; native Hook tab remains authoritative.")
