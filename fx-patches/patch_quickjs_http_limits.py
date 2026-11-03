#!/usr/bin/env python3
"""Apply bounded HTTP request inputs to the restored FX QuickJS host bridge."""
from pathlib import Path
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
runtime = module / "scripts/jsruntime"
host_path = runtime / "host.js"
readme_path = runtime / "README-zh-CN.md"
if not host_path.is_file() or host_path.stat().st_size < 5000:
    raise SystemExit(f"FX QuickJS host bridge is missing or incomplete: {host_path}")
if not readme_path.is_file():
    raise SystemExit(f"FX QuickJS runtime documentation is missing: {readme_path}")

source = host_path.read_text(encoding="utf-8")
begin = "  /* FX_HTTP_REQUEST_LIMITS_V1_BEGIN */"
end = "  /* FX_HTTP_REQUEST_LIMITS_V1_END */"
if begin in source or end in source:
    if source.count(begin) != 1 or source.count(end) != 1:
        raise SystemExit("partial FX QuickJS HTTP request-limit patch detected")
    if "request body exceeds 1 MiB" not in source or "request headers exceed 16 KiB" not in source:
        raise SystemExit("FX QuickJS HTTP request-limit patch is incomplete")
else:
    helper_anchor = "  function _fxRequest(options,cb) {\n"
    helper = r"""  /* FX_HTTP_REQUEST_LIMITS_V1_BEGIN */
  const _FX_HTTP_MAX_URL_CHARS = 4096;
  const _FX_HTTP_MAX_REQUEST_BYTES = 1024 * 1024;
  const _FX_HTTP_MAX_HEADER_BYTES = 16 * 1024;
  function _fxUtf8Size(value) {
    const text = String(value);
    let bytes = 0;
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      if (c <= 0x7f) bytes += 1;
      else if (c <= 0x7ff) bytes += 2;
      else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
        const next = text.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) { bytes += 4; i++; }
        else bytes += 3;
      } else bytes += 3;
    }
    return bytes;
  }
  /* FX_HTTP_REQUEST_LIMITS_V1_END */

  function _fxRequest(options,cb) {
"""
    if source.count(helper_anchor) != 1:
        raise SystemExit("QuickJS _fxRequest helper insertion anchor missing or ambiguous")
    source = source.replace(helper_anchor, helper, 1)

    def replace_once(old: str, new: str, label: str) -> None:
        nonlocal source
        count = source.count(old)
        if count != 1:
            raise SystemExit(f"QuickJS {label} anchor expected once, found {count}")
        source = source.replace(old, new, 1)

    replace_once(
        "    const url=String(options.url||options.uri||'');\n",
        "    const url=String(options.url||options.uri||'');\n"
        "    if(url.length>_FX_HTTP_MAX_URL_CHARS||/[\\x00-\\x20\\x7f]/.test(url)) "
        "throw new Error('HTTP URL is invalid or exceeds 4096 characters');\n",
        "URL bound",
    )
    replace_once(
        "    const headers=options.headers||{}, headerLines=[];\n"
        "    for(const k of Object.keys(headers)){\n"
        "      const v=String(headers[k]);\n"
        "      if(/\\r|\\n/.test(k+v)||/^(host|content-length|transfer-encoding)$/i.test(k)) "
        "throw new Error('unsafe HTTP header: '+k);\n"
        "      headerLines.push(k+': '+v);\n"
        "    }\n",
        "    const headers=options.headers||{}, headerLines=[];\n"
        "    let headerBytes=0;\n"
        "    for(const k of Object.keys(headers)){\n"
        "      const v=String(headers[k]);\n"
        "      if(!/^[!#$%&'*+.^_\\x60|~0-9A-Za-z-]+$/.test(k)||"
        "/[\\x00-\\x08\\x0a-\\x1f\\x7f]/.test(v)||"
        "/^(host|content-length|transfer-encoding)$/i.test(k)) "
        "throw new Error('unsafe HTTP header: '+k);\n"
        "      const line=k+': '+v;\n"
        "      headerBytes+=_fxUtf8Size(line)+2;\n"
        "      if(headerBytes>_FX_HTTP_MAX_HEADER_BYTES) "
        "throw new Error('HTTP request headers exceed 16 KiB');\n"
        "      headerLines.push(line);\n"
        "    }\n",
        "header validation",
    )
    replace_once(
        "    _fxWrite(tmp+'.headers',headerLines.join('\\n'));\n"
        "    _fxWrite(tmp+'.body',options.body==null?'':"
        "(typeof options.body==='string'?options.body:JSON.stringify(options.body)));\n",
        "    _fxWrite(tmp+'.headers',headerLines.join('\\n'));\n"
        "    const bodyValue=options.body==null?'':"
        "(typeof options.body==='string'?options.body:JSON.stringify(options.body));\n"
        "    const requestBody=bodyValue==null?'':String(bodyValue);\n"
        "    if(_fxUtf8Size(requestBody)>_FX_HTTP_MAX_REQUEST_BYTES) "
        "throw new Error('HTTP request body exceeds 1 MiB');\n"
        "    _fxWrite(tmp+'.body',requestBody);\n",
        "request body bound",
    )
    replace_once(
        "    const timeout=Math.max(1,Math.min(20,"
        "Number(options.timeout||globalThis.$httpClient.timeout||10)));\n",
        "    const requestedTimeout=Number(options.timeout||globalThis.$httpClient.timeout||10);\n"
        "    const timeout=Number.isFinite(requestedTimeout)?"
        "Math.max(1,Math.min(20,requestedTimeout)):10;\n",
        "timeout normalization",
    )
    host_path.write_text(source, encoding="utf-8")

readme = readme_path.read_text(encoding="utf-8")
tick = chr(96)
host_api = tick + "$httpClient" + tick
old = ("HTTP bridge 仅允许 " + tick + "http://" + tick + " 与 " +
       tick + "https://" + tick + "，单次 " + host_api + " 请求超时会限制在 1–20 秒、响应最多 8 MiB")
new = ("HTTP bridge 仅允许 " + tick + "http://" + tick + " 与 " +
       tick + "https://" + tick + "，URL 最多 4096 字符、请求体最多 1 MiB、"
       "请求头合计最多 16 KiB，单次 " + host_api + " 请求超时会限制在 1–20 秒、响应最多 8 MiB")
if old not in readme:
    raise SystemExit("QuickJS README HTTP limits documentation anchor missing")
readme_path.write_text(readme.replace(old, new, 1), encoding="utf-8")
print("Applied FX QuickJS HTTP URL/header/body limits and synchronized runtime documentation.")
