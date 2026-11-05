#!/system/bin/sh
# Audit108: a cache fallback must not be reported as a fresh successful download.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APPLY="$ROOT/scripts/apply.sh"
python3 - "$APPLY" <<'PY'
import sys
s=open(sys.argv[1], encoding='utf-8').read()
checks = {
 'cache marker declared per destination': '_hf_cache_marker="$_hf_dst.cache-used"' in s,
 'marker cleared before each fetch': 'rm -f "$_hf_cache_marker" 2>/dev/null' in s,
 'fresh cache hit marked': 'cp -f "$_hf_cache" "$_hf_dst" 2>/dev/null && { : > "$_hf_cache_marker";' in s,
 'fallback cache hit marked': 'using checksum-verified cached copy' in s and ': > "$_hf_cache_marker"' in s,
 'parent detects child-process marker': '[ -f "$_F.cache-used" ] && _cache_used=1' in s,
 'cached source status explicitly reported': 'record rule "$_entry" cached "使用校验通过的本地缓存' in s,
 'cached status avoids claiming fresh download': 'if [ "$_cache_used" = "1" ]; then' in s and 'record rule "$_entry" partial "下载与当前解析阶段完成' in s,
}
for label, ok in checks.items():
    print(('PASS' if ok else 'FAIL') + ': ' + label)
if not all(checks.values()): raise SystemExit(1)
PY
