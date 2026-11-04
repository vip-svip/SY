#!/usr/bin/env python3
"""Regression for Dia system HTTP proxy Activity and Quick Settings Tile."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
(ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java").read_text(encoding="utf-8")
activity = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyActivity.java").read_text(encoding="utf-8")
tile = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyTileService.java").read_text(encoding="utf-8")
state = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyState.java").read_text(encoding="utf-8")
java_test = ROOT / "scripts/tests/FxDiaWifiProxyStateHostTest.java"
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
assert "FxDiaWifiProxyState.evaluate(managed, current, expected, true)" in activity, \
    "Activity must compare the live system value with FX's applied value"
assert "FxDiaWifiProxyState.mayRestore(proxyStatus)" in activity, \
    "Activity must disable restoration when FX no longer owns the live value"
assert "EXTERNALLY_CHANGED" in activity and "FX 不会覆盖当前值" in activity, \
    "Activity must disclose external proxy ownership conflicts"
assert 'prefs().getString("draft_host", prefs().getString("host", "127.0.0.1"))' in activity
assert 'prefs().getString("draft_port", prefs().getString("port", "8080"))' in activity
assert 'hostInput.addTextChangedListener' in activity and 'portInput.addTextChangedListener' in activity
assert '.remove("draft_host").remove("draft_port").commit()' in activity, \
    "successful apply must atomically commit managed proxy state and clear drafts"
assert "FX_PROXY_ROLLBACK_FAILED" in activity and "已安全恢复修改前的系统代理" in activity, \
    "local preference commit failure must attempt a verified conditional OS rollback"
assert "FxDiaWifiProxyState.evaluate" in tile and "queryLiveState()" in tile, \
    "Quick Settings Tile must derive state from the live system proxy"
assert "refreshTile(after)" in tile and "postTileState(before)" in tile, \
    "Tile must render successful transitions and post refused transitions to the main looper"
assert "postTileState(FxDiaWifiProxyState.Status.UNKNOWN)" in tile, \
    "Tile read failures must post state changes to the main looper"
assert "refreshTile();" not in tile, "stale preference-only Tile renderer must be removed"
assert "EXTERNALLY_CHANGED" in tile and "未执行" in tile, \
    "Tile must refuse to overwrite externally changed proxy state"
assert "Status evaluate(boolean managed" in state and "Status.UNKNOWN" in state, \
    "shared classifier must distinguish unobservable state"
javac, java = shutil.which("javac"), shutil.which("java")
if not javac or not java:
    raise AssertionError("JDK host compiler/runtime required for proxy state regression")
with tempfile.TemporaryDirectory(prefix="fx-proxy-host-") as output:
    subprocess.run([javac, "-d", output,
                    str(ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaWifiProxyState.java"),
                    str(java_test)], check=True)
    subprocess.run([java, "-cp", output,
                    "de.privacyguard.adhook.imported.dia.FxDiaWifiProxyStateHostTest"], check=True)
assert r'host.split("\\.", -1)' in tile, "Tile host validation must split DNS labels on literal dots"
assert "value.replace('" + slash + "n', ' ').replace('" + slash + "r', ' ')" in tile, "Tile log sanitizer must use valid Java newline character literals"
for token in ('putString("previous", newPrevious)', 'putString("applied", target)', '.remove("previous").remove("applied")'):
    assert token in activity, "proxy persisted ownership/rollback behavior missing: " + token
for path in (
    ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java",
    ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java",
    ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java",
    ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java",
):
    source = path.read_text(encoding="utf-8")
    assert slash * 2 + '"' not in source, path.name + " contains a Java-breaking double-escaped Shell quote"
print("PASS: Dia Wi-Fi proxy Activity and Tile Java escapes, host validation, and shell ownership/rollback contract")
