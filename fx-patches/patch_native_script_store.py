#!/usr/bin/env python3
"""Install the native Script page settings.conf backend and preserve multiline script values."""
from pathlib import Path
import sys


def patch_webroot(path: Path) -> bool:
    if not path.is_file():
        raise SystemExit(f"canonical FX WebUI asset missing: {path}")
    source = path.read_text(encoding="utf-8")
    if "function pgUnescapeScript(s)" in source:
        if "pgEscapeScript(e.v)" not in source:
            raise SystemExit("partial native script multiline patch detected")
        return False
    parse_anchor = r"var v=(p[0]||'').replace(/\\n/g,'\n');"
    parse_replacement = r"var v=cur==='script'?pgUnescapeScript(p[0]||''):(p[0]||'').replace(/\\n/g,'\n');"
    if parse_anchor not in source:
        raise SystemExit("settings.conf script parser anchor missing")
    serialize_anchor = "out.push(pgSan(e.v)+'|'+pgSan(e.note)+'|'+(e.on?1:0))"
    serialize_replacement = "(n==='script'?pgEscapeScript(e.v):pgSan(e.v))+'|'+pgSan(e.note)+'|'+(e.on?1:0)"
    if serialize_anchor not in source:
        raise SystemExit("settings.conf list serializer anchor missing")
    helper = r'''function pgUnescapeScript(s){
  s=String(s==null?'':s);var out='';
  for(var i=0;i<s.length;i++){
    var c=s.charAt(i);
    if(c==='\\'&&i+1<s.length){
      var n=s.charAt(i+1);
      if(n==='\\'){out+='\\';i++;continue}
      if(n==='n'){out+='\n';i++;continue}
    }
    out+=c;
  }
  return out;
}
function pgEscapeScript(s){
  return String(s==null?'':s).replace(/\\/g,'\\\\').replace(/\r\n?|\n/g,'\\n').replace(/\|/g,'｜');
}
'''
    marker = "function pgParse(text){"
    if marker not in source:
        raise SystemExit("settings.conf parser declaration missing")
    source = source.replace(marker, helper + marker, 1)
    source = source.replace(parse_anchor, parse_replacement, 1)
    source = source.replace(serialize_anchor, serialize_replacement, 1)
    path.write_text(source, encoding="utf-8")
    return True


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_native_script_store.py MODULE_DIR")
    module = Path(sys.argv[1]).resolve()
    source = Path(__file__).with_name("native-script-list.sh")
    if not source.is_file():
        raise SystemExit(f"native script backend source missing: {source}")
    target = module / "scripts/jsruntime/native-list.sh"
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = source.read_bytes()
    changed = not target.is_file() or target.read_bytes() != payload
    if changed:
        target.write_bytes(payload)
    target.chmod(0o755)
    html_changed = patch_webroot(module / "webroot/index.html")
    print(f"native script-list backend {'installed' if changed else 'already current'}: {target}; multiline script config patched={str(html_changed).lower()}")


if __name__ == "__main__":
    main()
