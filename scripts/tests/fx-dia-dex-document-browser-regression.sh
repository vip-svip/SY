#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
DEX="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java"
INDEX="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexIndex.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$DEX" ] && [ -s "$INDEX" ] || fail "Dia DEX browser sources missing"
grep -Fq 'REQUEST_DEX_DOCUMENT' "$DEX" || fail "standalone DEX document picker missing"
grep -Fq 'Intent.ACTION_OPEN_DOCUMENT' "$DEX" || fail "DEX selection must use Android document picker"
grep -Fq 'FxDiaDexIndex.readDex(input,' "$DEX" || fail "selected DEX is not parsed by the bounded parser"
grep -Fq 'selected = null;' "$DEX" || fail "standalone file must clear stale target app selection"
grep -Fq 'MAX_DEX_BYTES = 96 * 1024 * 1024' "$INDEX" || fail "DEX parser size cap is missing"
! grep -Eq 'DexClassLoader|PathClassLoader|loadClass\(' "$DEX" || fail "DEX browser must remain read-only"
echo "PASS: Dia standalone DEX file browser uses SAF and bounded read-only parsing"
