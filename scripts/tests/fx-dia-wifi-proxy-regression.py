#!/usr/bin/env python3
"""Regression for the Dia system HTTP proxy's Java and shell quoting contract."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java").read_text(encoding="utf-8")
slash = chr(92)
assert slash * 2 + '"' not in source, "Java source contains a malformed double-escaped quote"
assert "tr -d '" + slash * 2 + "r'" in source, "shell CR stripping must receive one escaped CR sequence"
assert "printf 'PREVIOUS=%s" + slash * 2 + "nAPPLIED=%s" + slash * 2 + "n'" in source, \
    "root result fields must be separated by actual printf newlines"
assert 'output.split("' + slash * 2 + "r?" + slash * 2 + 'n")' in source, \
    "root result parser must split CRLF and LF output"
for token in (
    "FX_PROXY_CONFLICT",
    "FX_PROXY_WRITE_FAILED",
    "settings put global http_proxy",
    "settings delete global http_proxy",
    'putString("previous", newPrevious)',
    'putString("applied", target)',
    '.remove("previous").remove("applied")',
):
    assert token in source, f"proxy ownership/rollback behavior missing: {token}"
print("PASS: Dia Wi-Fi proxy Java escapes and shell ownership/rollback contract")
