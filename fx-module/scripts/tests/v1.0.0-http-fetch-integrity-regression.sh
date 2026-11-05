#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/pg-http-fetch-test.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
awk '/^pg_fetch\(\) \{/ {p=1} p {print} p && /^\}/ {exit}' "$ROOT/scripts/util.sh" > "$T/fetch.sh"
[ -s "$T/fetch.sh" ]
cat > "$T/curl" <<'MOCK'
#!/bin/sh
out=
url=
for arg in "$@"; do
  case "$arg" in
    -o) next_out=1; continue ;;
  esac
  if [ "${next_out:-0}" = 1 ]; then out=$arg; next_out=0; continue; fi
  case "$arg" in http://*|https://*) url=$arg ;; esac
done
case "$url" in
  *404*) printf 'Not Found\n' > "$out"; exit 22 ;;
  *) printf '0.0.0.0 ads.example.test\n' > "$out"; exit 0 ;;
esac
MOCK
chmod +x "$T/curl"
PATH="$T:$PATH"; export PATH
PG="$T/state"; export PG
mkdir -p "$PG"
pg_have() { command -v "$1" >/dev/null 2>&1; }
. "$T/fetch.sh"
if pg_fetch 'https://rules.example/404' "$T/bad.txt"; then
  echo 'FAIL: HTTP error response accepted as successful download' >&2; exit 1
fi
pg_fetch 'https://rules.example/good' "$T/good.txt"
grep -q 'ads.example.test' "$T/good.txt"
echo 'PrivacyGuard 1.0.0 HTTP fetch integrity regression: PASS'
