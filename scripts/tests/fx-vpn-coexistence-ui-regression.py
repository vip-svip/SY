#!/usr/bin/env python3
"""Guard the native VPN UI consumer for the published coexistence snapshot."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
source = MAIN.read_text(encoding="utf-8")
required = (
    "refreshVpnCoexistenceStatus",
    "/data/adb/privacyguard/vpn-coexistence.json",
    "FX_COEXISTENCE_STATUS_NOT_PUBLISHED",
    'json.optString("grade_cn", "状态未知")',
    'json.optString("verdict", "unknown")',
    'json.optString("route_probe", "unverified")',
    'json.optBoolean("external_vpn", false)',
    'json.optString("external_if", "")',
    'json.optString("dataplane", "unknown")',
    'json.optString("source", "unknown")',
    '"verified".equals(routeProbe)',
    'nativeAction("刷新 VPN 共存状态", null)',
)
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit("VPN coexistence UI consumer missing: " + ", ".join(missing))
print("PASS: native VPN controls read and render the published coexistence verdict")
