#!/usr/bin/env python3
"""Host-side contract for the opt-in EXIF metadata privacy policy."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
policy = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/ExifPrivacyPolicy.java"
hook = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
tests = ROOT / "adhook/app/src/test/java/de/privacyguard/adhook/ExifPrivacyPolicyTest.java"

for required in (policy, hook, tests):
    assert required.is_file(), f"missing EXIF privacy source: {required}"

source = policy.read_text(encoding="utf-8")
hook_source = hook.read_text(encoding="utf-8")
unit_tests = tests.read_text(encoding="utf-8")

for token in (
    'tag.startsWith("GPS")',
    '"Make".equals(tag)',
    '"Model".equals(tag)',
    'tag.startsWith("DateTime")',
    'tag.startsWith("OffsetTime")',
    'tag.startsWith("SubSecTime")',
    '"BodySerialNumber".equals(tag)',
    '"LensSerialNumber".equals(tag)',
    '"CameraOwnerName".equals(tag)',
    '"ImageUniqueID".equals(tag)',
    '"Artist".equals(tag)',
    '"Copyright".equals(tag)',
    '"Software".equals(tag)',
):
    assert token in source, f"EXIF redaction policy lost metadata family: {token}"

assert "ExifPrivacyPolicy.shouldRedactTag((String) key)" in hook_source, \
    "ExifInterface getter hook does not apply the EXIF privacy policy"
assert "ExifPrivacyPolicy.isGpsTag((String) key)" in hook_source, \
    "direct GPS accessor hook does not apply the GPS privacy policy"

for token in (
    "redactsGpsCoordinatesAndGpsMetadata",
    "redactsDeviceAndTimestampMetadata",
    "preservesUnrelatedImageMetadata",
    "directCoordinateAccessorsAreRedacted",
    "nullAndEmptyTagsAreSafe",
):
    assert token in unit_tests, f"EXIF unit-test coverage missing: {token}"

print("PASS: EXIF policy, ExifInterface getter wiring, direct GPS redaction and JUnit contract are covered")
