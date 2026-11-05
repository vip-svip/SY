#!/system/bin/sh
# Bounded HTTP(S) download for subscription content.
# Pipe through head so chunked/unknown-length responses cannot grow the temp
# file beyond 8 MiB + 1 byte. The extra byte is an overflow sentinel.
# HTTPS requests may redirect only to HTTPS, preventing credential-bearing URL
# redirects from silently downgrading to cleartext HTTP. Initial HTTP URLs remain
# supported for compatibility, but curl redirects from them must also be HTTPS.
set -u
url=${1:-}
out=${2:-}
[ -n "$url" ] && [ -n "$out" ] || exit 64
case "$url" in http://*|https://*) ;; *) exit 64 ;; esac
command -v head >/dev/null 2>&1 || exit 127
rcfile="$out.transfer-status.$$"
rm -f "$rcfile"
if command -v curl >/dev/null 2>&1; then
  (
    curl -fsSL --proto '=http,https' --proto-redir '=https' \
      --connect-timeout 6 --max-time 15 --max-filesize 8388608 \
      -A 'clash.meta' -H 'Accept: */*' -o - "$url"
    rc=$?
    printf '%s\n' "$rc" > "$rcfile"
    exit "$rc"
  ) | head -c 8388609 > "$out"
elif command -v wget >/dev/null 2>&1; then
  (
    wget -q -T 15 --max-redirect=0 --user-agent='clash.meta' -O - "$url"
    rc=$?
    printf '%s\n' "$rc" > "$rcfile"
    exit "$rc"
  ) | head -c 8388609 > "$out"
else
  rm -f "$out"
  exit 127
fi
size=$(wc -c < "$out" 2>/dev/null | tr -d ' ')
case "$size" in ''|*[!0-9]*) size=0 ;; esac
rc=$(cat "$rcfile" 2>/dev/null || printf 'unknown')
rm -f "$rcfile"
if [ "$size" -gt 8388608 ] || [ "$rc" != 0 ]; then
  rm -f "$out"
  exit 1
fi
[ "$size" -gt 0 ] || { rm -f "$out"; exit 1; }
exit 0
