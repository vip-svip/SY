#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
H="$ROOT/scripts/jsruntime/host.js"
grep -Fq 'Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10))' "$H"
grep -Fq 'globalThis.$utils={' "$H"
grep -Fq 'base64Encode(v)' "$H"
grep -Fq 'urlEncode(v)' "$H"
grep -Fq 'const _fxIsRocket=(_fxCompat==='"'"'shadowrocket'"'"'||_fxCompat==='"'"'rocket'"'"')' "$H"
grep -Fq 'result.statusText=' "$H"
printf '%s\n' 'jsruntime utils regression: PASS'
