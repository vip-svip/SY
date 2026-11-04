#!/usr/bin/env python3
"""Regression for original Yulong normal/vendor quickboot receiver compatibility."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
BOOT = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongBootReceiver.java"
MANIFEST = ROOT / "adhook/app/src/main/AndroidManifest.xml"

source = BOOT.read_text(encoding="utf-8")
manifest = ET.parse(MANIFEST).getroot()
android = "{http://schemas.android.com/apk/res/android}"
receiver = None
for candidate in manifest.findall("./application/receiver"):
    if candidate.get(android + "name", "").endswith("FxYulongBootReceiver"):
        receiver = candidate
        break
assert receiver is not None, "Shield boot receiver missing from manifest"

expected_actions = {
    "android.intent.action.BOOT_COMPLETED",
    "android.intent.action.MY_PACKAGE_REPLACED",
    "android.intent.action.QUICKBOOT_POWERON",
    "com.htc.intent.action.QUICKBOOT_POWERON",
}
actual_actions = {
    action.get(android + "name")
    for action in receiver.findall("./intent-filter/action")
}
assert expected_actions <= actual_actions, \
    "BootReceiver manifest must keep standard boot, package replace and both original QuickBoot broadcasts"
for action in expected_actions:
    assert action in source, f"BootReceiver does not accept {action}"

# Restore only the user-opted-in Shield services and do not silently restore
# Android permissions. Volume-key rescue is delivered by the accessibility
# onKeyEvent path; it must not start the foreground protection monitor alone.
assert 'prefs.getBoolean("protect_on", false) || prefs.getBoolean("shake_trigger_on", false)' in source
assert 'prefs.getBoolean("overlay_rescue_on", false)' in source
assert "Settings.canDrawOverlays(app)" in source
assert "FxYulongKeepAliveReceiver.refreshSchedule(app)" in source
assert 'prefs.getBoolean("volume_trigger_on"' not in source
print("PASS: Yulong standard/vendor QuickBoot broadcasts restore only opted-in FX Shield services")
