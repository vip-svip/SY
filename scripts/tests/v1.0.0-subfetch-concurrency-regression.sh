#!/bin/sh
set -eu

BASE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
if [ -s "$BASE_ROOT/fx-module/scripts/subfetch.sh" ]; then
  SOURCE_MODULE="$BASE_ROOT/fx-module"
elif [ -s "$BASE_ROOT/scripts/subfetch.sh" ]; then
  SOURCE_MODULE="$BASE_ROOT"
else
  echo "FAIL: cannot locate restored FX module from $BASE_ROOT" >&2
  exit 1
fi
for required in scripts/subfetch.sh scripts/subfetch-download.sh scripts/util.sh; do
  [ -s "$SOURCE_MODULE/$required" ] || {
    echo "FAIL: restored FX source is missing $required" >&2
    exit 1
  }
done

T=$(mktemp -d "/tmp/fx-subfetch-concurrency.XXXXXX")
cleanup(){ rm -rf "$T"; }
trap cleanup EXIT HUP INT TERM
MODULE="$T/module"
mkdir -p "$MODULE/scripts" "$T/bin" "$T/state"
cp "$SOURCE_MODULE/scripts/subfetch.sh" "$MODULE/scripts/subfetch.sh"
cp "$SOURCE_MODULE/scripts/subfetch-download.sh" "$MODULE/scripts/subfetch-download.sh"
cp "$SOURCE_MODULE/scripts/util.sh" "$MODULE/scripts/util.sh"
printf 'id=privacyguard\nname=FX test fixture\n' > "$MODULE/module.prop"
chmod 0755 "$MODULE/scripts/subfetch.sh" "$MODULE/scripts/subfetch-download.sh"

# The count file is deliberately updated without a second lock. If subfetch's
# per-URL cache lock is missing or ineffective, overlapping curl calls lose an
# increment and the final value will not be exactly two.
cat > "$T/bin/curl" <<'CURL'
#!/bin/sh
out=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      shift
      [ "$#" -gt 0 ] || exit 64
      out=$1
      ;;
    http://*|https://*) url=$1 ;;
  esac
  shift
done
[ -n "$url" ] || { echo "mock curl did not receive a URL" >&2; exit 64; }
countfile="$TEST_ROOT/count"
events="$TEST_ROOT/curl-events"
printf 'START|%s|%s\n' "$" "$(date +%s 2>/dev/null || echo 0)" >> "$events"
n=0
[ ! -f "$countfile" ] || n=$(cat "$countfile")
n=$((n + 1))
printf '%s\n' "$n" > "$countfile"
sleep 1
if [ "$n" -eq 1 ]; then
  body='vless://123e4567-e89b-12d3-a456-426614174000@edge-one.example:443?encryption=none#one'
else
  body='vless://123e4567-e89b-12d3-a456-426614174000@edge-two.example:443?encryption=none#two
trojan://secret@edge-three.example:443#three'
fi
if [ "$out" = '-' ]; then
  printf '%s\n' "$body"
else
  printf '%s\n' "$body" > "$out"
fi
printf 'END|%s|%s\n' "$" "$(date +%s 2>/dev/null || echo 0)" >> "$events"
CURL
chmod 0755 "$T/bin/curl"
export TEST_ROOT="$T/state"
export PATH="$T/bin:$PATH"

URL='https://example.invalid/rules'
PG="$T/state" sh "$MODULE/scripts/subfetch.sh" "$URL" --force > "$T/out1" 2> "$T/err1" &
p1=$!
PG="$T/state" sh "$MODULE/scripts/subfetch.sh" "$URL" --force > "$T/out2" 2> "$T/err2" &
p2=$!

set +e
wait "$p1"; rc1=$?
wait "$p2"; rc2=$?
set -e
if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; then
  echo "FAIL: subfetch workers exited non-zero (first=$rc1 second=$rc2)" >&2
  echo "--- worker 1 stdout ---" >&2; cat "$T/out1" >&2 || :
  echo "--- worker 1 stderr ---" >&2; cat "$T/err1" >&2 || :
  echo "--- worker 2 stdout ---" >&2; cat "$T/out2" >&2 || :
  echo "--- worker 2 stderr ---" >&2; cat "$T/err2" >&2 || :
  find "$T/state" -maxdepth 2 -print >&2
  exit 1
fi

for output in "$T/out1" "$T/out2"; do
  grep -Fq '"ok":1' "$output" || {
    echo "FAIL: subfetch did not return ok=1: $(cat "$output")" >&2
    exit 1
  }
done

key=$(printf '%s' "$URL" | cksum | awk '{print $1}')
body="$T/state/subs/$key.txt"
meta="$T/state/subs/$key.meta"
[ -s "$body" ] || { echo "FAIL: subscription body was not committed" >&2; exit 1; }
[ -s "$meta" ] || { echo "FAIL: subscription metadata was not committed" >&2; exit 1; }

actual_size=$(wc -c < "$body" | tr -d ' ')
actual_lines=$(awk 'END{print NR}' "$body")
meta_size=$(sed -n 's/^size=//p' "$meta" | head -1)
meta_lines=$(sed -n 's/^lines=//p' "$meta" | head -1)
[ "$actual_size" = "$meta_size" ] || {
  echo "FAIL: metadata size mismatch (body=$actual_size meta=$meta_size)" >&2
  exit 1
}
[ "$actual_lines" = "$meta_lines" ] || {
  echo "FAIL: metadata line count mismatch (body=$actual_lines meta=$meta_lines)" >&2
  exit 1
}

count=$(cat "$T/state/count" 2>/dev/null || echo missing)
[ "$count" = 2 ] || {
  echo "FAIL: expected exactly two serialized network requests, got $count" >&2
  echo "curl event timeline (START/END must alternate by PID):" >&2
  cat "$T/state/curl-events" >&2 || :
  echo "worker 1 stdout/stderr:" >&2; cat "$T/out1" "$T/err1" >&2 || :
  echo "worker 2 stdout/stderr:" >&2; cat "$T/out2" "$T/err2" >&2 || :
  find "$T/state/subs" -maxdepth 2 -print >&2 || :
  exit 1
}
grep -Fq 'edge-two.example' "$body" || {
  echo "FAIL: final cache does not contain the second successful response" >&2
  cat "$body" >&2
  exit 1
}
grep -Fq 'edge-three.example' "$body" || {
  echo "FAIL: final cache lost the second response's second line" >&2
  cat "$body" >&2
  exit 1
}
[ ! -d "$T/state/subs/.lock.$key" ] || {
  echo "FAIL: per-subscription lock directory leaked after both workers exited" >&2
  find "$T/state/subs/.lock.$key" -maxdepth 2 -print >&2
  exit 1
}
echo 'FX subscription cache concurrency regression: PASS'
