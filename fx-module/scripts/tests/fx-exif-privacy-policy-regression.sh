#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/ExifPrivacyPolicy.java"
TEST="$ROOT/scripts/tests/FxExifPrivacyPolicyHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "EXIF privacy policy source missing"
[ -s "$TEST" ] || fail "EXIF privacy Host test missing"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-exif-privacy.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
javac -d "$WORK" "$SOURCE" "$TEST" || fail "EXIF privacy Host test compilation failed"
java -cp "$WORK" de.privacyguard.adhook.FxExifPrivacyPolicyHostTest
