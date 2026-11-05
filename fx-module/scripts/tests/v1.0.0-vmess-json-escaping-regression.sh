#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vmess-json.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/edge.yaml" <<'YAML'
proxies:
  - name: 'Tokyo "quoted" \ node'
    type: vmess
    server: 2001:db8::1
    port: 443
    uuid: 'id"slash\tail'
    network: ws
    path: '/a"b\c'
    servername: 'sni.example'
    tls: true
  - name: Plain
    type: vless
    server: edge.example.com
    port: 8443
    uuid: abc
    tls: false
YAML
vpn_yaml_to_uri "$T/edge.yaml" > "$T/out"
python3 - "$T/out" <<'PY'
import base64,json,sys
lines=open(sys.argv[1],encoding='utf-8').read().splitlines()
vm=next(x for x in lines if x.startswith('vmess://'))
obj=json.loads(base64.b64decode(vm[8:]))
assert obj['ps']=='Tokyo "quoted" \\ node',repr(obj)
assert obj['add']=='[2001:db8::1]',repr(obj)
assert obj['id']=='id"slash\\tail',repr(obj)
assert obj['path']=='/a"b\\c',repr(obj)
assert obj['tls']=='tls',repr(obj)
vless=next(x for x in lines if x.startswith('vless://'))
assert 'security=none' in vless, vless
PY
sh -n "$ROOT/scripts/vpnsub.sh"
echo 'PASS: VMess JSON escaping, IPv6 authority, and VLESS TLS-off semantics'
