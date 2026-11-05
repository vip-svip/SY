#!/system/bin/sh
# Ensure the shared bounded downloader restricts redirect handling and caps bytes while streaming.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
S="$ROOT/scripts/subfetch.sh"
D="$ROOT/scripts/subfetch-download.sh"
grep -Fq 'subfetch-download.sh' "$S" || {
  echo 'FAIL: subscription fetch does not use the bounded download helper' >&2; exit 1;
}
grep -Fq "curl -fsSL --proto '=http,https' --proto-redir '=https'" "$D" || {
  echo 'FAIL: curl fetch does not restrict redirect protocols' >&2; exit 1;
}
grep -Fq -- '--max-filesize 8388608' "$D" || {
  echo 'FAIL: curl must enforce server-declared size limit' >&2; exit 1;
}
grep -Fq 'head -c 8388609' "$D" || {
  echo 'FAIL: unknown-length/chunked response is not bounded while streaming' >&2; exit 1;
}
grep -Fq 'wget -q -T 15 --max-redirect=0 --user-agent=' "$D" || {
  echo 'FAIL: wget fallback must not follow redirects' >&2; exit 1;
}
grep -Fq 'timeout 20 sh "$MODDIR/scripts/subfetch-download.sh"' "$S" || {
  echo 'FAIL: bounded downloader is not wrapped in the overall timeout when available' >&2; exit 1;
}
sh -n "$S"
sh -n "$D"
printf '%s\n' 'PASS: subscription downloader restricts redirects and hard-caps streaming responses'
