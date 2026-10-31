#!/usr/bin/env python3
"""Preserve Clash WS Host headers and gRPC service names through FX import."""
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
sub = root / "scripts/vpnsub.sh"
core = root / "scripts/vpncore.sh"
s = sub.read_text(encoding="utf-8")

if "FX_CLASH_TRANSPORT_FIELDS_V1" not in s:
    changes = [
        ('alpn = ""; reality = "" }',
         'alpn = ""; reality = ""; ws_host = ""; service = "" }'),
        ('%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher, flow, fp, pbk, sid, alpn, reality',
         '%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher, flow, fp, pbk, sid, alpn, reality, ws_host, service'),
        ('else if (k == "alpn") { gsub(/[\\[\\]\\\" ]/, "", v); alpn = v }',
         'else if (k == "alpn") { gsub(/[\\[\\]\\\" ]/, "", v); alpn = v }\n'
         '  else if (k == "host") ws_host = v\n'
         '  else if (k == "service-name" || k == "service_name" || k == "grpc-service-name" || k == "grpc_service_name") service = v'),
        ('_yreality; do',
         '_yreality _yws_host _yservice; do'),
        ('        [ -n "$_yalpn" ] && _yv_extra="$_yv_extra&alpn=$(printf \'%s\' "$_yalpn" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"',
         '        [ -n "$_yalpn" ] && _yv_extra="$_yv_extra&alpn=$(printf \'%s\' "$_yalpn" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_yws_host" ] && _yv_extra="$_yv_extra&host=$(printf \'%s\' "$_yws_host" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_yservice" ] && _yv_extra="$_yv_extra&serviceName=$(printf \'%s\' "$_yservice" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"'),
        ('      trojan)\n        echo "trojan://${_ypw_uri}@${_yh}:${_yp}?sni=${_ysni_uri}#${_yn_uri}"',
         '      trojan)\n        _yt_extra=\n'
         '        [ -n "$_yws_host" ] && _yt_extra="&host=$(printf \'%s\' "$_yws_host" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_yservice" ] && _yt_extra="$_yt_extra&serviceName=$(printf \'%s\' "$_yservice" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        echo "trojan://${_ypw_uri}@${_yh}:${_yp}?sni=${_ysni_uri}&type=${_ynet:-tcp}&path=${_ypath_uri:-/}${_yt_extra}#${_yn_uri}"'),
    ]
    for old, new in changes:
        if old not in s:
            raise SystemExit("missing vpnsub transport patch anchor: " + old[:100])
        s = s.replace(old, new, 1)
    s = s.replace("# FX_CLASH_REALITY_FIELDS_V1", "# FX_CLASH_REALITY_FIELDS_V1\n# FX_CLASH_TRANSPORT_FIELDS_V1", 1)
    sub.write_text(s, encoding="utf-8")

if "FX_CLASH_VMESS_WS_SNI_V1" not in s:
    old = '''        _jsni=$(vpn_json_escape "$_ysni")
        _jtls=
        case "$_ytls" in true|yes|1|tls) _jtls=tls ;; esac
        _yj=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","scy":"%s","net":"%s","path":"%s","host":"%s","tls":"%s"}' \\
          "$_jps" "$_jhost" "$_jport" "$_jid" "$_jscy" "$_jnet" "$_jpath" "$_jsni" "$_jtls")'''
    new = '''        _jsni=$(vpn_json_escape "$_ysni_raw")
        _jws_host=$(vpn_json_escape "${_yws_host:-$_ysni_raw}")
        _jtls=
        case "$_ytls" in true|yes|1|tls) _jtls=tls ;; esac
        _yj=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","scy":"%s","net":"%s","path":"%s","host":"%s","sni":"%s","tls":"%s"}' \\
          "$_jps" "$_jhost" "$_jport" "$_jid" "$_jscy" "$_jnet" "$_jpath" "$_jws_host" "$_jsni" "$_jtls")'''
    if old not in s:
        raise SystemExit("missing VMess WS/SNI JSON patch anchor")
    s = s.replace(old, new, 1)
    s = s.replace("# FX_CLASH_TRANSPORT_FIELDS_V1", "# FX_CLASH_TRANSPORT_FIELDS_V1\n# FX_CLASH_VMESS_WS_SNI_V1", 1)
    sub.write_text(s, encoding="utf-8")

s = core.read_text(encoding="utf-8")
if "FX_CLASH_WS_HOST_TRANSPORT_V1" not in s:
    old = '_path=$(qsdec "$_q" path); _svc=$(qsdec "$_q" serviceName)'
    new = '_path=$(qsdec "$_q" path); _ws_host=$(qsdec "$_q" host); _svc=$(qsdec "$_q" serviceName)'
    if s.count(old) != 2:
        raise SystemExit("expected two VLESS/Trojan transport query anchors; found %d" % s.count(old))
    s = s.replace(old, new)
    old = 'ws) printf \',"transport":{"type":"ws","path":"%s"}\' "${_path:-/}" ;;\n        grpc) printf \',"transport":{"type":"grpc","service_name":"%s"}\' "${_svc:-}" ;;'
    new = 'ws)\n          if [ -n "$_ws_host" ]; then printf \',"transport":{"type":"ws","path":"%s","headers":{"Host":"%s"}}\' "${_path:-/}" "$_ws_host"; else printf \',"transport":{"type":"ws","path":"%s"}\' "${_path:-/}"; fi\n          ;;\n        grpc) printf \',"transport":{"type":"grpc","service_name":"%s"}\' "${_svc:-}" ;;'
    if old not in s:
        raise SystemExit("missing VLESS WebSocket transport output anchor")
    s = s.replace(old, new, 1)
    # Trojan branch has a distinct indentation; add the same Host header there.
    if old not in s:
        raise SystemExit("missing Trojan WebSocket transport output anchor")
    s = s.replace(old, new, 1)
    s = s.replace("# ---- 节点 URI → sing-box outbound JSON ----", "# FX_CLASH_WS_HOST_TRANSPORT_V1\n# ---- 节点 URI → sing-box outbound JSON ----", 1)
    core.write_text(s, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-clash-transport-yaml-regression.sh"
test.write_text(r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-clash-transport.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/transport.yaml" <<'YAML'
proxies:
  - name: VLESS WebSocket
    type: vless
    server: edge.example.com
    port: 443
    uuid: 123e4567-e89b-12d3-a456-426614174000
    network: ws
    tls: true
    ws-opts:
      path: /gateway
      headers:
        Host: cdn.example.com
  - name: VLESS gRPC
    type: vless
    server: grpc.example.com
    port: 443
    uuid: 123e4567-e89b-12d3-a456-426614174001
    network: grpc
    tls: true
    grpc-opts:
      grpc-service-name: tunnel.Service
  - name: Trojan WebSocket
    type: trojan
    server: trojan.example.com
    port: 443
    password: secret
    network: ws
    sni: trojan.example.com
    ws-opts:
      path: /trojan
      headers:
        Host: ws.example.com
  - name: VMess WebSocket
    type: vmess
    server: vmess.example.com
    port: 443
    uuid: 123e4567-e89b-12d3-a456-426614174003
    network: ws
    tls: true
    servername: sni.vmess.example.com
    ws-opts:
      path: /vmess
      headers:
        Host: cdn.vmess.example.com
YAML
vpn_yaml_to_uri "$T/transport.yaml" > "$T/out"
[ "$(wc -l < "$T/out" | tr -d ' ')" = 4 ] || { cat "$T/out"; exit 1; }
grep -Fq 'type=ws' "$T/out"
grep -Fq 'path=/gateway' "$T/out"
grep -Fq 'host=cdn.example.com' "$T/out"
grep -Fq 'serviceName=tunnel.Service' "$T/out"
grep -Fq 'host=ws.example.com' "$T/out"
python3 - "$T/out" <<'PY'
import json,sys,subprocess,os
uris=open(sys.argv[1]).read().splitlines()
for uri,expected in [(uris[0],('ws','/gateway','cdn.example.com')),(uris[1],('grpc','tunnel.Service',None)),(uris[2],('ws','/trojan','ws.example.com'))]:
    cmd='. "$MODDIR/scripts/vpncore.sh"; singbox_node_outbound "$1" test-tag'
    out=subprocess.check_output(['sh','-c',cmd,'sh',uri],env=os.environ,text=True)
    obj=json.loads(out)
    assert obj['transport']['type']==expected[0],obj
    if expected[0]=='ws':
        assert obj['transport']['path']==expected[1],obj
        assert obj['transport']['headers']['Host']==expected[2],obj
    else:
        assert obj['transport']['service_name']==expected[1],obj
vmess_uri=uris[3].split('://',1)[1]
import base64
raw=base64.b64decode(vmess_uri + '=' * ((4-len(vmess_uri)%4)%4))
vmess=json.loads(raw)
assert vmess['host']=='cdn.vmess.example.com',vmess
assert vmess['sni']=='sni.vmess.example.com',vmess
out=subprocess.check_output(['sh','-c','. "$MODDIR/scripts/vpncore.sh"; singbox_node_outbound "$1" vmess-tag','sh',uris[3]],env=os.environ,text=True)
obj=json.loads(out)
assert obj['tls']['server_name']=='sni.vmess.example.com',obj
assert obj['transport']['headers']['Host']=='cdn.vmess.example.com',obj
PY
echo 'PASS: Clash WS Host headers, gRPC service names, and VMess SNI survive import and sing-box generation'
''', encoding="utf-8")
test.chmod(0o755)
