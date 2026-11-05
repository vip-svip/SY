#!/system/bin/sh
# Build the MITM URL rewrite manifest from imported settings, preserving the
# last known-good manifest if the candidate is empty or malformed.
set -eu
MODDIR=${FX_MODDIR:-${MODDIR:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}}
PG=${PG:-/data/adb/privacyguard}
SETTINGS=${FX_SETTINGS:-$PG/settings.conf}
OUTDIR="$PG/mitm"
OUT="$OUTDIR/url-rewrite.conf"
TMP="$OUTDIR/.url-rewrite.conf.$$"
mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR" 2>/dev/null || :
: > "$TMP"
section=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '[list:urlrewrite]'*) section=1; continue ;;
    '['*) section=0 ;;
  esac
  [ "$section" = 1 ] || continue
  case "$line" in ''|\#*) continue ;; esac
  enabled=${line##*|}
  [ "$enabled" = 1 ] || continue
  payload=${line%%|*}
  note=$(printf '%s' "$line" | awk -F'|' '{print $(NF-1)}')
  [ "$note" = FXURLREWRITE_B64 ] || continue
  decoded=$(printf '%s' "$payload" | base64 -d 2>/dev/null) || { rm -f "$TMP"; echo 'invalid URL Rewrite base64; retaining previous manifest' >&2; exit 1; }
  # One rule per settings line; forbid newlines and reject obviously malformed
  # records here. The Go engine performs full regex/action/target validation.
  case "$decoded" in *'\n'*|*'\r'*) rm -f "$TMP"; echo 'multiline URL Rewrite rule rejected' >&2; exit 1 ;; esac
  case "$decoded" in *' - '*) printf '%s\n' "$decoded" >> "$TMP" ;; *) rm -f "$TMP"; echo 'malformed URL Rewrite rule; retaining previous manifest' >&2; exit 1 ;; esac
done < "$SETTINGS"
if [ ! -s "$TMP" ]; then
  # Empty imported list is valid, but do not erase a prior active manifest when
  # settings could not be read. An existing readable settings file is required.
  [ -r "$SETTINGS" ] || { rm -f "$TMP"; echo 'settings unreadable; retaining previous manifest' >&2; exit 1; }
fi
chmod 600 "$TMP"
# Validate the complete candidate with the same Go parser used by the live MITM
# engine before publication. If the binary is unavailable or rejects a regex,
# action, or redirect target, retain the previous manifest unchanged.
VALIDATOR=${FX_MITM_BIN:-"$MODDIR/bin/arm64/pg-mitm"}
[ -x "$VALIDATOR" ] || VALIDATOR="$MODDIR/bin/arm/pg-mitm"
[ -x "$VALIDATOR" ] || { rm -f "$TMP"; echo 'MITM validator unavailable; retaining previous URL Rewrite manifest' >&2; exit 1; }
if ! "$VALIDATOR" -mode validate-urlrewrite -manifest "$TMP"; then
  rm -f "$TMP"
  echo 'URL Rewrite candidate rejected; retaining previous manifest' >&2
  exit 1
fi
# Atomic replacement: readers see either the old complete file or the new one.
mv -f "$TMP" "$OUT"
chmod 600 "$OUT"
