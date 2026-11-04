#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_quickjs_http_limits.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "QuickJS HTTP hardening patcher is missing"
python3 -m py_compile "$PATCHER" || fail "QuickJS HTTP hardening patcher has invalid Python syntax"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-qjs-http-limits.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module/scripts/jsruntime" "$T/module/scripts/tests"
cat > "$T/module/scripts/jsruntime/host.js" <<'HOST'
(function () {
  const _fxSTD = std, _fxOS = os;
  function _fxRequest(options,cb) {
    if(typeof options==='string') options={url:options};
    options=options||{};
    const url=String(options.url||options.uri||'');
    const method=String(options.method||'GET').toUpperCase();
    if(!/^https?:\/\//i.test(url)) throw new Error('only http/https URLs are allowed');
    if(!/^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$/.test(method)) throw new Error('unsupported HTTP method');
    const headers=options.headers||{}, headerLines=[];
    for(const k of Object.keys(headers)){
      const v=String(headers[k]);
      if(/\r|\n/.test(k+v)||/^(host|content-length|transfer-encoding)$/i.test(k)) throw new Error('unsafe HTTP header: '+k);
      headerLines.push(k+': '+v);
    }
    const tmp=_fxStateDir+'/http-'+_fxOS.getpid()+'-'+Date.now();
    _fxWrite(tmp+'.headers',headerLines.join('\n'));
    _fxWrite(tmp+'.body',options.body==null?'':(typeof options.body==='string'?options.body:JSON.stringify(options.body)));
    const timeout=Math.max(1,Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10)));
  }
})();
HOST

for name in v1.0.0-jsruntime-utils-regression.sh v1.0.0-third-party-api-compat-regression.sh; do
  cat > "$T/module/scripts/tests/$name" <<'COMPAT'
grep -Fq 'Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10))' "$H"
COMPAT
done
python3 - "$T/module/scripts/jsruntime/host.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8") + "\n// Fixture padding to match the stable host bridge minimum size.\n" + "x" * 6000, encoding="utf-8")
PY
python3 - "$T/module/scripts/jsruntime/README-zh-CN.md" <<'PY'
from pathlib import Path
import sys
tick = chr(96)
Path(sys.argv[1]).write_text(
    "- HTTP bridge 仅允许 " + tick + "http://" + tick + " 与 " + tick + "https://" + tick
    + "，单次 " + tick + "$httpClient" + tick
    + " 请求超时会限制在 1–20 秒、响应最多 8 MiB；没有 curl 时失败关闭。\n",
    encoding="utf-8",
)
PY
python3 "$PATCHER" "$T/module" >/dev/null || fail "HTTP hardening patch failed on a known host fixture"

for name in v1.0.0-jsruntime-utils-regression.sh v1.0.0-third-party-api-compat-regression.sh; do
  compat="$T/module/scripts/tests/$name"
  grep -Fq 'Number.isFinite(requestedTimeout)?Math.max(1,Math.min(20,requestedTimeout)):10' "$compat" || fail "$name still asserts the obsolete timeout expression"
  grep -Fq '_FX_HTTP_MAX_URL_CHARS = 4096' "$compat" || fail "$name does not assert the URL bound"
  grep -Fq 'HTTP request body exceeds 1 MiB' "$compat" || fail "$name does not assert the body bound"
  grep -Fq 'HTTP request headers exceed 16 KiB' "$compat" || fail "$name does not assert the header bound"
done
HOST_FILE="$T/module/scripts/jsruntime/host.js"
README_FILE="$T/module/scripts/jsruntime/README-zh-CN.md"
grep -Fq 'FX_HTTP_REQUEST_LIMITS_V1_BEGIN' "$HOST_FILE" || fail "HTTP limit helpers were not installed"
grep -Fq '_FX_HTTP_MAX_URL_CHARS = 4096' "$HOST_FILE" || fail "URL bound missing"
grep -Fq '_FX_HTTP_MAX_REQUEST_BYTES = 1024 * 1024' "$HOST_FILE" || fail "request-body bound missing"
grep -Fq '_FX_HTTP_MAX_HEADER_BYTES = 16 * 1024' "$HOST_FILE" || fail "request-header bound missing"
grep -Fq 'HTTP request body exceeds 1 MiB' "$HOST_FILE" || fail "request body error path missing"
grep -Fq 'HTTP request headers exceed 16 KiB' "$HOST_FILE" || fail "request header error path missing"
grep -Fq 'Number.isFinite(requestedTimeout)' "$HOST_FILE" || fail "invalid timeout fallback missing"
grep -Fq '请求体最多 1 MiB' "$README_FILE" || fail "HTTP request bounds are not documented"
before_host=$(sha256sum "$HOST_FILE" | awk '{print $1}')
before_readme=$(sha256sum "$README_FILE" | awk '{print $1}')
before_utils=$(sha256sum "$T/module/scripts/tests/v1.0.0-jsruntime-utils-regression.sh" | awk '{print $1}')
before_compat=$(sha256sum "$T/module/scripts/tests/v1.0.0-third-party-api-compat-regression.sh" | awk '{print $1}')
python3 "$PATCHER" "$T/module" >/dev/null || fail "second HTTP hardening patch was not idempotent"
[ "$before_host" = "$(sha256sum "$HOST_FILE" | awk '{print $1}')" ] || fail "second patch changed host.js"
[ "$before_readme" = "$(sha256sum "$README_FILE" | awk '{print $1}')" ] || fail "second patch changed README"
[ "$before_utils" = "$(sha256sum "$T/module/scripts/tests/v1.0.0-jsruntime-utils-regression.sh" | awk '{print $1}')" ] || fail "second patch changed compatibility utils regression"
[ "$before_compat" = "$(sha256sum "$T/module/scripts/tests/v1.0.0-third-party-api-compat-regression.sh" | awk '{print $1}')" ] || fail "second patch changed third-party compatibility regression"
if [ -n "${1:-}" ]; then
  MODULE=$(CDPATH= cd -- "$1" && pwd)
  ACTUAL="$MODULE/scripts/jsruntime/host.js"
  DOC="$MODULE/scripts/jsruntime/README-zh-CN.md"
  [ -s "$ACTUAL" ] || fail "restored QuickJS host.js missing"
  [ -s "$DOC" ] || fail "restored QuickJS README missing"
  grep -Fq 'FX_HTTP_REQUEST_LIMITS_V1_BEGIN' "$ACTUAL" || fail "restored host lacks HTTP input limits"
  grep -Fq '请求头合计最多 16 KiB' "$DOC" || fail "restored runtime documentation is stale"
  sh -n "$MODULE/scripts/jsruntime/http.sh" || fail "restored HTTP bridge shell syntax invalid"
  for name in v1.0.0-jsruntime-utils-regression.sh v1.0.0-third-party-api-compat-regression.sh; do
    compat="$MODULE/scripts/tests/$name"
    [ -s "$compat" ] || fail "restored QuickJS compatibility test missing: $name"
    grep -Fq 'Number.isFinite(requestedTimeout)?Math.max(1,Math.min(20,requestedTimeout)):10' "$compat" || fail "restored $name keeps the obsolete timeout expression"
    grep -Fq 'HTTP request headers exceed 16 KiB' "$compat" || fail "restored $name lacks the header size assertion"
  done
fi
echo "PASS: QuickJS host caps URL, request body and headers; rejects control characters, normalizes timeout and patches idempotently"
