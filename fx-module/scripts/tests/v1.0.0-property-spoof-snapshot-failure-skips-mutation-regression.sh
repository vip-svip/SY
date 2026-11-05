#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SRC="$ROOT/post-fs-data.sh"
grep -Fq 'SNAP_TMP="$SNAP.tmp.$$"' "$SRC"
grep -Fq '[ -s "$SNAP_TMP" ] && grep -q '\''^ro.boot.verifiedbootstate='\'' "$SNAP_TMP"' "$SRC"
grep -Fq 'mv -f "$SNAP_TMP" "$SNAP"' "$SRC"
grep -Fq 'if [ "$SNAP_OK" = "1" ]; then' "$SRC"
grep -Fq 'skipped all resetprop spoofing' "$SRC"
printf '%s\n' 'PASS: property spoofing is gated on an atomically published original-value snapshot'
