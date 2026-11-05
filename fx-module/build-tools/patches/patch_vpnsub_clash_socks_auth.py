#!/usr/bin/env python3
"""Keep SOCKS5 username/password authentication intact in Clash YAML imports."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
p = root / "scripts/vpnsub.sh"
s = p.read_text(encoding="utf-8")
if "FX_CLASH_SOCKS_AUTH_V1" not in s:
    changes = [
        ('ws_host = ""; service = "" }',
         'ws_host = ""; service = ""; username = "" }'),
        ('%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher, flow, fp, pbk, sid, alpn, reality, ws_host, service',
         '%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher, flow, fp, pbk, sid, alpn, reality, ws_host, service, username'),
        ('else if (k == "service-name" || k == "service_name" || k == "grpc-service-name" || k == "grpc_service_name") service = v',
         'else if (k == "service-name" || k == "service_name" || k == "grpc-service-name" || k == "grpc_service_name") service = v\n'
         '  else if (k == "username" || k == "user") username = v'),
        ('_yreality _yws_host _yservice; do',
         '_yreality _yws_host _yservice _yusername; do'),
        ('      socks5)\n        echo "socks5://${_yh}:${_yp}#${_yn}"',
         '      socks5)\n'
         '        if [ -n "$_yusername" ] || [ -n "$_ypw" ]; then\n'
         '          # Do not silently turn an authenticated SOCKS profile into anonymous access.\n'
         '          [ -n "$_yusername" ] && [ -n "$_ypw" ] || continue\n'
         '          _ysocks_user=$(printf "%s" "$_yusername" | sed "s/%/%25/g; s/@/%40/g; s/:/%3A/g; s/#/%23/g; s/ /%20/g; s/&/%26/g; s/+/%2B/g; s/=/\\%3D/g; s/;/%3B/g")\n'
         '          echo "socks5://${_ysocks_user}:${_ypw_uri}@${_yh}:${_yp}#${_yn_uri}"\n'
         '        else\n'
         '          echo "socks5://${_yh}:${_yp}#${_yn_uri}"\n'
         '        fi'),
    ]
    for old, new in changes:
        if old not in s:
            raise SystemExit("missing SOCKS5 YAML patch anchor: " + old[:100])
        s = s.replace(old, new, 1)
    s = s.replace("# FX_CLASH_TRANSPORT_FIELDS_V1", "# FX_CLASH_TRANSPORT_FIELDS_V1\n# FX_CLASH_SOCKS_AUTH_V1", 1)
    p.write_text(s, encoding="utf-8")

core = root / "scripts/vpncore.sh"
s = core.read_text(encoding="utf-8")
if "FX_URI_PERCENT_DECODER_POSIX_V1" not in s:
    old = '''urldec() { printf '%b' "$(echo "$1" | sed 's/%/\\\\x/g')"; }'''
    new = """# FX_URI_PERCENT_DECODER_POSIX_V1
urldec() {
  # POSIX-shell portable percent decoding; dash does not consistently decode \\xHH via printf %b.
  printf '%s' "$1" | awk '
    BEGIN { hex = "0123456789ABCDEF" }
    {
      s = $0
      while (match(s, /%[0-9A-Fa-f][0-9A-Fa-f]/)) {
        printf "%s", substr(s, 1, RSTART - 1)
        pair = toupper(substr(s, RSTART + 1, 2))
        hi = index(hex, substr(pair, 1, 1)) - 1
        lo = index(hex, substr(pair, 2, 1)) - 1
        printf "%c", hi * 16 + lo
        s = substr(s, RSTART + 3)
      }
      printf "%s", s
    }
  '
}"""
    if old not in s:
        raise SystemExit("missing POSIX URI decoder patch anchor")
    s = s.replace(old, new, 1)
    core.write_text(s, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-clash-socks-auth-yaml-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-clash-socks.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/socks.yaml" <<'YAML'
proxies:
  - name: Authenticated SOCKS
    type: socks5
    server: socks-auth.example.com
    port: 1080
    username: test:user
    password: p@ss/w?rd
  - name: Anonymous SOCKS
    type: socks5
    server: socks-open.example.com
    port: 1080
  - name: Incomplete SOCKS Auth
    type: socks5
    server: socks-invalid.example.com
    port: 1080
    username: only-user
YAML
vpn_yaml_to_uri "$T/socks.yaml" > "$T/out"
[ "$(wc -l < "$T/out" | tr -d ' ')" = 2 ] || { cat "$T/out"; echo 'FAIL: incomplete auth must not silently downgrade'; exit 1; }
grep -Fq 'socks5://test%3Auser:p%40ss%2Fw%3Frd@socks-auth.example.com:1080' "$T/out"
grep -Fq 'socks5://socks-open.example.com:1080' "$T/out"
. "$ROOT/scripts/vpncore.sh"
[ "$(urldec 'a%3Ab%40c%2Fd%3Fe%20f%25')" = "a:b@c/d?e f%" ] || { echo 'FAIL: POSIX URI percent decoder'; exit 1; }
python3 - "$T/out" <<'PY'
import json,sys,subprocess,os
uris=open(sys.argv[1]).read().splitlines()
for uri in uris:
    out=subprocess.check_output(['sh','-c','. "$MODDIR/scripts/vpncore.sh"; singbox_node_outbound "$1" socks-tag','sh',uri],env=os.environ,text=True)
    obj=json.loads(out)
    if 'socks-auth' in uri:
        assert obj['username']=='test:user',obj
        assert obj['password']=='p@ss/w?rd',obj
    else:
        assert 'username' not in obj and 'password' not in obj,obj
PY
echo 'PASS: Clash SOCKS5 authentication is preserved and incomplete credentials fail closed'
''', encoding="utf-8")
test.chmod(0o755)
