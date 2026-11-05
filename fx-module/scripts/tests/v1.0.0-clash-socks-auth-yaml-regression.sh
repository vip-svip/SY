#!/system/bin/sh
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
