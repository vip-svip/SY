#!/usr/bin/env python3
"""Regression for Java-to-shell quoting across migrated FX entrypoints."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SLASH = chr(92)
FILES = (
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTileService.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyTileService.java",
    "adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongIntegrityActivity.java",
)
for relative in FILES:
    source = (ROOT / relative).read_text(encoding="utf-8")
    assert SLASH * 2 + '"' not in source, f"{relative}: malformed Java-escaped shell quotes remain"
    assert SLASH * 4 + "n" not in source, f"{relative}: shell newline is over-escaped"
    assert SLASH * 4 + "r" not in source, f"{relative}: shell carriage return is over-escaped"

ad = (ROOT / FILES[0]).read_text(encoding="utf-8")
assert 'r.output.split("' + SLASH * 2 + "r?" + SLASH * 2 + 'n")' in ad, \
    "Yulong Ad output must parse LF/CRLF records"
dia = (ROOT / FILES[5]).read_text(encoding="utf-8")
assert "printf 'installed=%s" + SLASH * 2 + "nsha256=%s" in dia, \
    "Frida binary import must emit line-separated install metadata"
assert "FX_GADGET_LOG_SYMLINK_REJECTED" in dia, "Frida log reader must reject symlinked paths"
integrity = (ROOT / FILES[7]).read_text(encoding="utf-8")
for token in ("MODULE=missing", "STATE=disabled", "STATE=marked-for-removal", "shell-syntax-error"):
    assert token in integrity, "Shield module integrity checks missing: " + token
print("PASS: Yulong, Dia Frida and Shield migrated Java shell string escaping")
