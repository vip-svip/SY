#!/usr/bin/env python3
"""Static migration contract for Yulong's network-protection Quick Settings tile."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "adhook/app/src/main/AndroidManifest.xml"
VPN_TILE = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongVpnTileService.java"
AD_TILE = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTileService.java"

ANDROID = "{http://schemas.android.com/apk/res/android}"
manifest = ET.parse(MANIFEST).getroot()
vpn_service = None
ad_service = None
for service in manifest.findall("./application/service"):
    name = service.get(ANDROID + "name", "")
    if name.endswith("FxYulongVpnTileService"):
        vpn_service = service
    elif name.endswith("FxYulongAdTileService"):
        ad_service = service

assert vpn_service is not None, "FX VPN Quick Settings tile is not registered"
assert vpn_service.get(ANDROID + "permission") == "android.permission.BIND_QUICK_SETTINGS_TILE"
assert vpn_service.get(ANDROID + "exported") == "true"
assert any(
    action.get(ANDROID + "name") == "android.service.quicksettings.action.QS_TILE"
    for action in vpn_service.findall("./intent-filter/action")
), "VPN tile intent filter missing"
assert ad_service is not None, "independent Yulong ad-filter tile must remain registered"

source = VPN_TILE.read_text(encoding="utf-8")
for token in (
    "yulong-vpn-control.sh",
    'vpnCommand("status")',
    'vpnCommand(action)',
    '"vpn_on"',
    '"vpn_mode"',
    '"root_proxy_on"',
    '"root_proxy_known"',
    "Tile.STATE_ACTIVE",
    "Tile.STATE_INACTIVE",
    "Tile.STATE_UNAVAILABLE",
    "RootAccess.execute",
    "ArrayBlockingQueue<>(1)",
    "togglePending.compareAndSet(false, true)",
    "VPN_NO_NODE_SELECTED",
    "worker.shutdownNow()",
):
    assert token in source, f"VPN tile contract missing: {token}"

assert not re.search(r"\.\s*start(?:Foreground)?Service\s*\(", source), \
    "VPN tile must use the canonical FX controller, not start a legacy Android service"
assert not re.search(r"new\s+Intent\s*\([^;]*(?:AdBlockVpnService|RootProxyService)", source), \
    "VPN tile must not create intents for legacy network services"

ad_source = AD_TILE.read_text(encoding="utf-8")
assert 'command("list")' in ad_source and 'command("ad-master " + next)' in ad_source
assert 'tile.setLabel("FX 广告过滤")' in ad_source
print("PASS: Yulong Quick Settings maps to FX's single VPN controller; independent ad-master tile remains separate")

CONTROLLER = ROOT / "scripts/yulong-vpn-control.sh"
ROOT_PROXY_PATCHER = ROOT / "fx-patches/patch_yulong_root_proxy.py"
WIDGET = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdWidgetProvider.java"
MAIN = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"

controller = CONTROLLER.read_text(encoding="utf-8")
for token in (
    '"root_proxy_on":%s',
    '"root_proxy_known":%s',
    "try_root_proxy_without_node()",
    "vpn_external_compat",
    "VPN_STATUS_UNAVAILABLE",
    "toggle refused to mutate an unknown route",
):
    assert token in controller, f"shared VPN/Root Proxy controller contract missing: {token}"

patcher = ROOT_PROXY_PATCHER.read_text(encoding="utf-8")
assert 'vpn_control_source = repo / "scripts/yulong-vpn-control.sh"' in patcher
assert "vpn_control_target.chmod(0o755)" in patcher

widget = WIDGET.read_text(encoding="utf-8")
for token in ('"root_proxy_on"', '"root_proxy_known"', "current.protectedNow()", "state.rootProxy"):
    assert token in widget, f"home-screen widget does not consume shared protection state: {token}"

main = MAIN.read_text(encoding="utf-8")
assert 'sh \\"$MP/scripts/yulong-vpn-control.sh\\"' in main
assert 'optBoolean("root_proxy_on", false)' in main
assert 'optBoolean("root_proxy_known", false)' in main
print("PASS: VPN tile, home widget, main dashboard and release restore patcher share VPN/Root Proxy state")

assert 'nativeVpnRootCommand("start", "")' in main
assert 'nativeVpnRootCommand("stop", "")' in main
assert "已启动 FX Root Proxy DNS 保护（不代表第三方 VPN 已连接）" in main
assert "stopCurrentRouteWithController" in main
print("PASS: legacy home shortcut uses common VPN/Root Proxy start/stop when required")
