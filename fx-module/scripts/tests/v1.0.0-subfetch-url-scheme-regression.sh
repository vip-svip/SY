#!/system/bin/sh
# Ensure remote subscription fetches cannot use non-HTTP protocols.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
S="$ROOT/scripts/subfetch.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-scheme.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
for url in 'file:///etc/passwd' 'ftp://example.invalid/sub' 'gopher://example.invalid/' 'data:text/plain,hello'; do
  out=$(PG="$T/state" MODDIR="$ROOT" sh "$S" "$url" --force)
  printf '%s' "$out" | grep -Fq 'unsupported URL scheme' || { echo "FAIL: accepted $url" >&2; exit 1; }
done
# Valid HTTP(S) URLs continue to the ordinary fetch/cache path; invalid URLs must
# fail before creating subscription state or attempting network access.
[ ! -d "$T/state/subs" ] || { echo 'FAIL: rejected URL created subscription cache' >&2; exit 1; }
printf '%s\n' 'PASS: subfetch rejects non-HTTP(S) schemes before cache/network work'
