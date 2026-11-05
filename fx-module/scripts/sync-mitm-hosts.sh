#!/system/bin/sh
# Atomically publish explicitly enabled MITM hostnames. An empty list is safe:
# the engine will pass all unmatched TLS through without terminating it.
set -eu
MODDIR=${FX_MODDIR:-${MODDIR:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}}
PG=${PG:-/data/adb/privacyguard}
SETTINGS=${FX_SETTINGS:-$PG/settings.conf}
OUTDIR="$PG/mitm"
OUT="$OUTDIR/hostnames.conf"
TMP="$OUTDIR/.hostnames.conf.$$"
mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR" 2>/dev/null || :
[ -r "$SETTINGS" ] || { echo 'settings unreadable; retaining previous MITM hostname allowlist' >&2; exit 1; }
: > "$TMP"
section=0
count=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '[list:mitmhost]'*) section=1; continue ;;
    '['*) section=0 ;;
  esac
  [ "$section" = 1 ] || continue
  case "$line" in ''|\#*) continue ;; esac
  enabled=${line##*|}
  [ "$enabled" = 1 ] || continue
  host=${line%%|*}
  host=$(printf '%s' "$host" | tr 'A-Z' 'a-z' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\.$//')
  case "$host" in
    '*.'*) base=${host#*.} ;;
    *'*'*) rm -f "$TMP"; echo "invalid MITM hostname wildcard; retaining previous list: $host" >&2; exit 1 ;;
    *) base=$host ;;
  esac
  printf '%s' "$base" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' || {
    rm -f "$TMP"; echo "invalid MITM hostname; retaining previous list: $host" >&2; exit 1;
  }
  count=$((count + 1))
  [ "$count" -le 1024 ] || { rm -f "$TMP"; echo 'MITM hostname limit (1024) exceeded; retaining previous list' >&2; exit 1; }
  printf '%s\n' "$host" >> "$TMP"
done < "$SETTINGS"
sort -u "$TMP" -o "$TMP"
chmod 600 "$TMP"
mv -f "$TMP" "$OUT"
chmod 600 "$OUT" 2>/dev/null || :
printf '{"ok":true,"hosts":%s}\n' "$(wc -l < "$OUT" | tr -d ' ')"
