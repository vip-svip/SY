#!/system/bin/sh
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
