#!/system/bin/sh
# HTTP bridge for QuickJS scripts; no eval or shell interpolation of user values.
set -u
[ "$#" -eq 6 ] || exit 64
url=$1 method=$2 bodyfile=$3 outbody=$4 headersfile=$5 timeout=$6
case "$url" in http://*|https://*) ;; *) echo 'unsupported URL scheme' >&2; exit 65 ;; esac
case "$timeout" in ''|*[!0-9]*) timeout=20 ;; esac
[ "$timeout" -ge 1 ] 2>/dev/null || timeout=20
[ "$timeout" -le 120 ] 2>/dev/null || timeout=120
: > "$outbody" || exit 73
# Keep script-controlled uploads within the same bounded payload budget as responses.
body_size=$(wc -c < "$bodyfile" 2>/dev/null | tr -d " ")
case "$body_size" in ''|*[!0-9]*) echo "unable to determine HTTP request body size" >&2; exit 74 ;; esac
[ "$body_size" -le 8388608 ] || { echo "HTTP request body exceeds 8 MiB" >&2; exit 75; }
if command -v curl >/dev/null 2>&1; then
  set -- curl -sS -L --max-redirs 5 --proto '=http,https' --proto-redir '=https' --max-filesize 8388608 --max-time "$timeout" --connect-timeout 8 -X "$method" -D "$outbody.headers" -o "$outbody" -w '%{http_code}'
  if [ -s "$bodyfile" ]; then set -- "$@" --data-binary "@$bodyfile"; fi
  while IFS= read -r h || [ -n "$h" ]; do
    [ -n "$h" ] || continue
    case "$h" in *"$(printf '\r')"*) h=${h%"$(printf '\r')"} ;; esac
    case "$h" in *:* ) set -- "$@" -H "$h" ;; *) echo "invalid HTTP header" >&2; exit 65 ;; esac
  done < "$headersfile"
  set -- "$@" "$url"
  code=$("$@") || exit $?
  size=$(wc -c < "$outbody" 2>/dev/null | tr -d ' ')
  case "$size" in ''|*[!0-9]*) exit 74 ;; esac
  [ "$size" -le 8388608 ] || { echo 'HTTP response exceeds 8 MiB' >&2; exit 75; }
  printf '%s\n' "$code" > "$headersfile.status"
  exit 0
fi
# Do not fall back to wget: device/busybox wget variants do not expose a
# consistently portable redirect-protocol restriction, so an HTTPS request
# could be downgraded to HTTP after a redirect. Script HTTP APIs require curl.
echo 'curl is required for safe HTTP bridge requests (wget fallback disabled)' >&2
exit 69
