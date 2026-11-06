#!/usr/bin/env python3
"""Install the native Script page settings.conf backend and preserve local JS source."""
from pathlib import Path
import sys

import os
import stat
import tempfile


def atomic_write_bytes(path: Path, payload: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise SystemExit(f"refusing to replace symlink: {path}")
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
        try:
            directory_fd = os.open(str(path.parent), os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except OSError:
            pass
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def atomic_write_text(path: Path, content: str, mode: int) -> None:
    atomic_write_bytes(path, content.encode("utf-8"), mode)


def patch_webroot(path: Path) -> bool:
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f"canonical FX WebUI asset missing or unsafe: {path}")
    source = path.read_text(encoding="utf-8")
    if "function pgDecodeScriptValue(s)" in source:
        if "FXSRC_B64:'+pgB64(e.v)" not in source:
            raise SystemExit("partial native script-source codec patch detected")
        return False
    parse_anchor = r"var v=(p[0]||'').replace(/\\n/g,'\n');"
    parse_replacement = r"var v=cur==='script'?pgDecodeScriptValue(p[0]||''):(p[0]||'').replace(/\\n/g,'\n');"
    if parse_anchor not in source:
        raise SystemExit("settings.conf script parser anchor missing")
    serialize_anchor = "out.push(pgSan(e.v)+'|'+pgSan(e.note)+'|'+(e.on?1:0))"
    serialize_replacement = "out.push((n==='script'?(String(e.v||'').indexOf('https://')===0?pgEscapeScript(e.v):'FXSRC_B64:'+pgB64(e.v)):pgSan(e.v))+'|'+pgSan(e.note)+'|'+(e.on?1:0))"
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
function pgDecodeScriptValue(s){
  s=String(s==null?'':s);
  if(s.indexOf('FXSRC_B64:')===0){
    try{return decodeURIComponent(escape(atob(s.substring(10))))}
    catch(e){throw new Error('本地脚本配置损坏：Base64 解码失败')}
  }
  return pgUnescapeScript(s);
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
    atomic_write_text(path, source, stat.S_IMODE(path.stat().st_mode))
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
    if target.is_symlink():
        raise SystemExit(f"native script backend target is a symlink: {target}")
    changed = not target.is_file() or target.read_bytes() != payload
    if changed:
        atomic_write_bytes(target, payload, 0o755)
    elif stat.S_IMODE(target.stat().st_mode) != 0o755:
        target.chmod(0o755)
    runner_source = Path(__file__).with_name("native-script-run.sh")
    if not runner_source.is_file():
        raise SystemExit(f"native local-script runner source missing: {runner_source}")
    runner_target = module / "scripts/jsruntime/local-run.sh"
    runner_payload = runner_source.read_bytes()
    if runner_target.is_symlink():
        raise SystemExit(f"native local-script runner target is a symlink: {runner_target}")
    runner_changed = not runner_target.is_file() or runner_target.read_bytes() != runner_payload
    if runner_changed:
        atomic_write_bytes(runner_target, runner_payload, 0o755)
    elif stat.S_IMODE(runner_target.stat().st_mode) != 0o755:
        runner_target.chmod(0o755)
    html_changed = patch_webroot(module / "webroot/index.html")
    print(f"native script-list backend {'installed' if changed else 'already current'}: {target}; "
          f"local JS runner {'installed' if runner_changed else 'already current'}: {runner_target}; "
          f"local JS codec patched={str(html_changed).lower()}")


if __name__ == "__main__":
    main()
