#!/usr/bin/env python3
"""Regression for Dia system HTTP proxy Activity and Quick Settings Tile."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
(ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java").read_text(encoding="utf-8")
activity = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java").read_text(encoding="utf-8")
tile = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyTileService.java").read_text(encoding="utf-8")
slash = chr(92)

def assert_proxy_contract(label, source):
    assert slash * 2 + '"' not in source, label + " contains a malformed double-escaped Java quote"
    assert "tr -d '" + slash * 2 + "r'" in source, label + " must pass one escaped CR sequence to tr"
    assert "printf 'PREVIOUS=%s" + slash * 2 + "nAPPLIED=%s" + slash * 2 + "n'" in source, label + " must emit newline-separated values"
    assert 'output.split("' + slash * 2 + "r?" + slash * 2 + 'n")' in source, label + " must parse LF and CRLF output"
    for token in ("FX_PROXY_CONFLICT", "FX_PROXY_WRITE_FAILED", "settings put global http_proxy", "settings delete global http_proxy"):
        assert token in source, label + " missing proxy ownership/rollback behavior: " + token

assert_proxy_contract("Dia Wi-Fi proxy Activity", activity)
assert_proxy_contract("Dia Wi-Fi proxy Quick Settings Tile", tile)
assert 'host.split("\\\\.", -1)' in tile, "Tile host validation must split DNS labels on literal dots"
assert "value.replace('" + slash + "n', ' ').replace('" + slash + "r', ' ')" in tile, "Tile log sanitizer must use valid Java newline character literals"
for token in ('putString("previous", newPrevious)', 'putString("applied", target)', '.remove("previous").remove("applied")'):
    assert token in activity, "proxy persisted ownership/rollback behavior missing: " + token
print("PASS: Dia Wi-Fi proxy Activity and Tile Java escapes, host validation, and shell ownership/rollback contract")
