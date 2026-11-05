#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-subfetch-concurrency.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module"
cp -a "$ROOT/." "$T/module/"
# Redirect the module's fixed runtime state path into this isolated test tree.
mkdir -p "$T/bin" "$T/state"
printf '#!%s\n' "$(command -v sh)" > "$T/bin/curl"
cat > "$T/bin/curl.body" <<'CURL'
out=''; url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; out=$1 ;;
    http://*|https://*) url=$1 ;;
  esac
  shift
done
countfile="$TEST_ROOT/count"
# Calls should be serialized, so this read/increment/write remains deterministic.
n=0; [ ! -f "$countfile" ] || n=$(cat "$countfile")
n=$((n+1)); printf '%s\n' "$n" > "$countfile"
sleep 1
if [ "$n" -eq 1 ]; then
  body='vless://123e4567-e89b-12d3-a456-426614174000@edge-one.example:443?encryption=none#one'
else
  body='vless://123e4567-e89b-12d3-a456-426614174000@edge-two.example:443?encryption=none#two
trojan://secret@edge-three.example:443#three'
fi
if [ "$out" = '-' ]; then printf '%s\n' "$body"; else printf '%s\n' "$body" > "$out"; fi
CURL
cat "$T/bin/curl.body" >> "$T/bin/curl"
rm -f "$T/bin/curl.body"
chmod 755 "$T/bin/curl"
export TEST_ROOT="$T/state" PATH="$T/bin:$PATH"
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" 'https://example.invalid/rules' --force > "$T/out1" & p1=$!
PG="$T/state" MODDIR="$T/module" sh "$T/module/scripts/subfetch.sh" 'https://example.invalid/rules' --force > "$T/out2" & p2=$!
wait "$p1"
wait "$p2"
key=$(printf '%s' 'https://example.invalid/rules' | cksum | awk '{print $1}')
body="$T/state/subs/$key.txt"
meta="$T/state/subs/$key.meta"
[ -s "$body" ] && [ -s "$meta" ]
actual_size=$(wc -c < "$body" | tr -d ' ')
actual_lines=$(awk 'END{print NR}' "$body")
meta_size=$(sed -n 's/^size=//p' "$meta" | head -1)
meta_lines=$(sed -n 's/^lines=//p' "$meta" | head -1)
[ "$actual_size" = "$meta_size" ]
[ "$actual_lines" = "$meta_lines" ]
[ "$(cat "$T/state/count")" -eq 2 ]
[ ! -d "$T/state/subs/.lock.$key" ]
echo 'FX subscription cache concurrency regression: PASS'
