#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
# Large text must be paged into a bounded editor, with a retry window long enough
# for first-time line counting on big files. Parsing must not allocate map/filter arrays.
grep -q 'var FE_PAGE=40, FE_BYTES=32768' "$UI"
grep -q '读取超时（30 秒）' "$UI"
grep -q 'function eachLine(source,fn)' "$UI"
! sed -n '/function parseSub(text)/,/^}/p' "$UI" | grep -q 'split(/\\r?\\n/).map'
grep -q "feCmd('page',spec,page+' '+FE_PAGE+' '+FE_BYTES)" "$UI"
grep -q "feWriteAndCommit(text,spec,'replacepage'" "$UI"
echo 'FX large-content editor memory regression: PASS'
