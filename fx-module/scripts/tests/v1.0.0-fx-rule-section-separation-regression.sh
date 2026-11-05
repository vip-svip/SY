#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CONF="$ROOT/scripts/default.conf"
UTIL="$ROOT/scripts/util.sh"
# The shipped cosmetic entries must be in [list:rule], not [list:fx].
awk '
  /^\[list:rule\][[:space:]]*$/ { section="rule"; next }
  /^\[list:fx\][[:space:]]*$/ { section="fx"; next }
  /^\[/ { section="" }
  section=="rule" && /builtin:\/\/NoAppDownload\.txt\|/ { splash=1 }
  section=="rule" && /builtin:\/\/Adblock_Watermark\.txt\|/ { watermark=1 }
  section=="rule" && /builtin:\/\/AdultSite_AdPopup\.txt\|/ { adult=1 }
  section=="rule" && /builtin:\/\/Adblock_Warning_Removal\.txt\|/ { anti=1 }
  section=="fx" && /NoAppDownload\.txt|Adblock_Watermark\.txt|AdultSite_AdPopup\.txt|Adblock_Warning_Removal\.txt|AdultSite_AdHosts\.txt/ { bad=1 }
  END { exit !(splash && watermark && adult && anti && !bad) }
' "$CONF" || { echo 'FAIL: cosmetic entries must be separate from FX rules' >&2; exit 1; }
grep -Fq 'moved cosmetic entries out of [list:fx] into [list:rule]' "$UTIL"
grep -Fq 'Always repair legacy/misplaced cosmetic entries' "$UTIL"
printf '%s\n' 'FX/general-rule section separation regression: PASS'
