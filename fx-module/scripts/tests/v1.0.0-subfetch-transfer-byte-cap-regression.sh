#!/system/bin/sh
# Regression: the subscription downloader must cap the file itself while
# streaming, even when the server does not declare Content-Length.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
D="$ROOT/scripts/subfetch-download.sh"
# Redirects must not downgrade to cleartext HTTP; guard subscription URL/token safety.
grep -Fq -- "--proto-redir '=https'" "$D" || { echo 'FAIL: curl redirects must be HTTPS-only' >&2; exit 1; }
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-cap.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'CURL'
#!/bin/sh
out=''
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift; out=$1 ;; esac
  shift
done
[ "$out" = '-' ] || exit 64
cat "$FIXTURE"
CURL
chmod 755 "$T/bin/curl"
printf 'proxies:\n  - {name: Tokyo, type: vless, server: edge.example, port: 443}\n' > "$T/small"
PATH="$T/bin:$PATH" FIXTURE="$T/small" sh "$D" 'https://sub.example.test/sub' "$T/out"
cmp -s "$T/small" "$T/out" || { echo 'FAIL: small response changed during bounded download' >&2; exit 1; }
truncate -s 9437184 "$T/oversize"
if PATH="$T/bin:$PATH" FIXTURE="$T/oversize" sh "$D" 'https://sub.example.test/sub' "$T/oversize.out"; then
  echo 'FAIL: chunked/unknown-length response above 8 MiB was accepted' >&2; exit 1
fi
[ ! -e "$T/oversize.out" ] || { echo 'FAIL: oversized partial body was retained' >&2; exit 1; }
if PATH="$T/bin:$PATH" FIXTURE="$T/small" sh "$D" 'file:///etc/passwd' "$T/invalid.out"; then
  echo 'FAIL: non-HTTP(S) URL was accepted' >&2; exit 1
fi
echo 'PASS: subscription transfer is byte-capped while streaming and rejects invalid schemes'
