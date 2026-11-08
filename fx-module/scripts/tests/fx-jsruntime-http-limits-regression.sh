#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATCHER="$ROOT/build-tools/patches/patch_quickjs_http_limits.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCHER" ] || fail "QuickJS HTTP safety patcher is missing"
python3 -m py_compile "$PATCHER" || fail "QuickJS HTTP safety patcher has invalid Python syntax"
T=$(mktemp -d /tmp/fx-qjs-http-safety.XXXXXX)
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
    _fxWrite(tmp+'.headers',headerLines.join('\\n'));
    _fxWrite(tmp+'.body',options.body==null?'':(typeof options.body==='string'?options.body:JSON.stringify(options.body)));
    const timeout=Math.max(1,Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10)));
  }
})();
HOST
python3 - "$T/module/scripts/jsruntime/host.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8") + "\n// Fixture padding to match the stable host bridge minimum size.\n" + "x" * 6000, encoding="utf-8")
PY

for name in v1.0.0-jsruntime-utils-regression.sh v1.0.0-third-party-api-compat-regression.sh; do
  cat > "$T/module/scripts/tests/$name" <<'COMPAT'
grep -Fq 'Math.min(20,Number(options.timeout||globalThis.$httpClient.timeout||10))' "$H"
COMPAT
done
python3 - "$T/module/scripts/jsruntime/README-zh-CN.md" <<'PY'
from pathlib import Path
import sys
tick = chr(96)
Path(sys.argv[1]).write_text(
    "- HTTP bridge 仅允许 " + tick + "http://" + tick + " 与 " + tick + "https://" + tick
    + "，单次 " + tick + "$httpClient" + tick
    + " 请求超时会限制在 1–20 秒、响应最多 8 MiB；为了防止不同 wget 实现的重定向协议限制不一致，HTTP bridge 没有 curl 时会失败关闭。\\n",
    encoding="utf-8",
)
PY
cp -a "$T/module" "$T/baseline"
python3 "$PATCHER" "$T/module" >/dev/null || fail "HTTP safety patch failed on a known host fixture"

HOST_FILE="$T/module/scripts/jsruntime/host.js"
README_FILE="$T/module/scripts/jsruntime/README-zh-CN.md"
grep -Fq 'FX_HTTP_REQUEST_SAFETY_V1_BEGIN' "$HOST_FILE" || fail "HTTP safety marker missing"
grep -Fq 'HTTP URL contains invalid control or whitespace characters' "$HOST_FILE" || fail "URL control-byte validation missing"
grep -Fq 'unsafe HTTP header:' "$HOST_FILE" || fail "HTTP header syntax/authority protection missing"
grep -Fq 'requestBody' "$HOST_FILE" || fail "request body is not staged"
grep -Fq 'host|content-length|transfer-encoding' "$HOST_FILE" || fail "managed HTTP headers are not protected"
if grep -Eq '_FX_HTTP_MAX|exceeds 1 MiB|exceeds 16 KiB|4096 characters|response exceeds 8 MiB' "$HOST_FILE" "$README_FILE"; then
  fail "QuickJS HTTP host still contains a fixed size/character ceiling"
fi
grep -Fq '不设固定产品字节/字符上限' "$README_FILE" || fail "unbounded HTTP capacity is not documented"
grep -Fq 'Number.isFinite(requestedTimeout)' "$HOST_FILE" || fail "invalid timeout fallback missing"
for name in v1.0.0-jsruntime-utils-regression.sh v1.0.0-third-party-api-compat-regression.sh; do
  compat="$T/module/scripts/tests/$name"
  grep -Fq 'Number.isFinite(requestedTimeout)?Math.max(1,Math.min(20,requestedTimeout)):10' "$compat" || fail "$name retains obsolete timeout expression"
  grep -Fq 'HTTP URL contains invalid control or whitespace characters' "$compat" || fail "$name does not assert URL syntax validation"
  grep -Fq 'unsafe HTTP header:' "$compat" || fail "$name does not assert HTTP header validation"
  grep -Fq 'requestBody' "$compat" || fail "$name does not assert file-backed request body staging"
done

before_host=$(sha256sum "$HOST_FILE" | awk '{print $1}')
before_readme=$(sha256sum "$README_FILE" | awk '{print $1}')
before_utils=$(sha256sum "$T/module/scripts/tests/v1.0.0-jsruntime-utils-regression.sh" | awk '{print $1}')
before_compat=$(sha256sum "$T/module/scripts/tests/v1.0.0-third-party-api-compat-regression.sh" | awk '{print $1}')
python3 "$PATCHER" "$T/module" >/dev/null || fail "second HTTP safety patch was not idempotent"
[ "$before_host" = "$(sha256sum "$HOST_FILE" | awk '{print $1}')" ] || fail "second patch changed host.js"
[ "$before_readme" = "$(sha256sum "$README_FILE" | awk '{print $1}')" ] || fail "second patch changed README"
[ "$before_utils" = "$(sha256sum "$T/module/scripts/tests/v1.0.0-jsruntime-utils-regression.sh" | awk '{print $1}')" ] || fail "second patch changed compatibility utils regression"
[ "$before_compat" = "$(sha256sum "$T/module/scripts/tests/v1.0.0-third-party-api-compat-regression.sh" | awk '{print $1}')" ] || fail "second patch changed third-party compatibility regression"

# Negative case: ambiguous insertion anchors must fail before writing host.js.
mkdir -p "$T/ambiguous"
cp -a "$T/baseline/." "$T/ambiguous/"
printf '\n  function _fxRequest(options,cb) {\n  }\n' >> "$T/ambiguous/scripts/jsruntime/host.js"
ambiguous_before=$(sha256sum "$T/ambiguous/scripts/jsruntime/host.js" | awk '{print $1}')
if python3 "$PATCHER" "$T/ambiguous" >/dev/null 2>&1; then
  fail "ambiguous _fxRequest anchor was accepted"
fi
[ "$ambiguous_before" = "$(sha256sum "$T/ambiguous/scripts/jsruntime/host.js" | awk '{print $1}')" ] || fail "ambiguous anchor failure modified host.js"

# Negative case: a partial marker pair must be rejected without rewriting files.
mkdir -p "$T/partial"
cp -a "$T/baseline/." "$T/partial/"
printf '\n  /* FX_HTTP_REQUEST_SAFETY_V1_BEGIN */\n' >> "$T/partial/scripts/jsruntime/host.js"
partial_before=$(sha256sum "$T/partial/scripts/jsruntime/host.js" | awk '{print $1}')
if python3 "$PATCHER" "$T/partial" >/dev/null 2>&1; then
  fail "partial HTTP safety marker pair was accepted"
fi
[ "$partial_before" = "$(sha256sum "$T/partial/scripts/jsruntime/host.js" | awk '{print $1}')" ] || fail "partial-marker failure modified host.js"

if [ "$#" -gt 0 ]; then
  MODULE=$(CDPATH= cd -- "$1" && pwd)
  ACTUAL="$MODULE/scripts/jsruntime/host.js"
  DOC="$MODULE/scripts/jsruntime/README-zh-CN.md"
  [ -s "$ACTUAL" ] || fail "restored QuickJS host.js missing"
  [ -s "$DOC" ] || fail "restored QuickJS README missing"
  grep -Fq 'FX_HTTP_REQUEST_SAFETY_V1_BEGIN' "$ACTUAL" || fail "restored host lacks HTTP safety patch"
  if grep -Eq '_FX_HTTP_MAX|exceeds 1 MiB|exceeds 16 KiB|4096 characters|response exceeds 8 MiB' "$ACTUAL" "$DOC"; then
    fail "restored runtime contains an arbitrary HTTP size/character ceiling"
  fi
  grep -Fq '不设固定产品字节/字符上限' "$DOC" || fail "restored HTTP capacity documentation is stale"
  sh -n "$MODULE/scripts/jsruntime/http.sh" || fail "restored HTTP bridge shell syntax invalid"
fi
echo "PASS: QuickJS HTTP is size-unbounded while validating URL/header syntax and preserving timeout normalization"
