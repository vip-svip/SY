#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/DeveloperExecutableDescriptor.java"
TEST="$ROOT/scripts/tests/FxKotlinHookSignatureHostTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "DeveloperExecutableDescriptor source missing"
[ -s "$TEST" ] || fail "Kotlin signature Host test missing"
grep -Fq "kotlin.BooleanArray" "$TEST" || fail "Kotlin primitive-array erasure coverage missing"
grep -Fq "kotlin.collections.MutableList" "$TEST" || fail "Kotlin collection erasure coverage missing"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fx-kotlin-hook-signature.XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
javac -d "$WORK" "$SOURCE" "$TEST" || fail "Kotlin signature Host test compilation failed"
java -cp "$WORK" de.privacyguard.adhook.FxKotlinHookSignatureHostTest
