#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
BE="$ROOT/scripts/fileedit.sh"
grep -q 'var FE_PAGE=40, FE_BYTES=32768' "$UI"
grep -q '读取超时（30 秒）' "$UI"
grep -q 'id="fePageText" class="fe-page-text"' "$UI"
grep -q "if(k==='savepage')return feDoSavePage()" "$UI"
grep -q "feWriteAndCommit(text,spec,'replacepage'" "$UI"
grep -q 'function feTempPath()' "$UI"
grep -q 'function feWriteAndCommit(text,spec,op,argsBuilder)' "$UI"
grep -q 'if(b64===null)' "$UI"
! grep -q 'pg-fe-edit.tmp' "$UI"
grep -q 'replacepage)' "$BE"
grep -q 'page transform failed; original preserved' "$BE"
# Exercise the exact page replacement transform used by the backend.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'one\ntwo\nthree\nfour\n' > "$tmp/source"
printf 'TWO\nSECOND LINE' > "$tmp/replacement"
awk -v start=2 -v count=2 -v repl="$tmp/replacement" '
  BEGIN { rn=0; while((getline l < repl)>0) rep[++rn]=l }
  NR < start { print; next }
  NR == start { for(i=1;i<=rn;i++) print rep[i]; next }
  NR < start + count { next }
  { print }
  END { if(start > NR) for(i=1;i<=rn;i++) print rep[i] }
' "$tmp/source" > "$tmp/actual"
printf 'one\nTWO\nSECOND LINE\nfour\n' > "$tmp/expected"
cmp -s "$tmp/expected" "$tmp/actual"
# Ensure only one page is represented in the textarea path; no whole-file cat API.
! grep -q "feCmd('cat',spec)" "$UI"
echo 'PASS: traditional paginated text editor regression'
