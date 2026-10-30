#!/bin/sh
set -eu
SRC="adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
PARSER="adhook/app/src/main/java/de/privacyguard/adhook/UnifiedHookConfigParser.java"
POLICY="adhook/app/src/main/java/de/privacyguard/adhook/MediaStorePrivacyPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'installMediaStorePrivacyHooks' "$SRC" || fail 'ContentResolver query hook missing'
grep -q 'new android.database.MatrixCursor(original.getColumnNames())' "$SRC" || fail 'empty cursor construction missing'
grep -q 'original.close()' "$SRC" || fail 'original media cursor close missing'
grep -q 'case "block_mediastore"' "$PARSER" || fail 'MediaStore config parser missing'
grep -q 'com.android.providers.media.documents' "$POLICY" || fail 'Media Documents authority filter missing'
grep -q 'processPackageCount != 1' "$POLICY" || fail 'shared-process fail-open missing'
if grep -q 'com.android.externalstorage.documents' "$POLICY"; then fail 'generic SAF authority must remain untouched'; fi
echo 'FX API101 MediaStore privacy regression: PASS'
