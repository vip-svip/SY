#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-clash-reality.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/reality.yaml" <<'YAML'
proxies:
  - name: Reality Vision
    type: vless
    server: edge.example.com
    port: 443
    uuid: 123e4567-e89b-12d3-a456-426614174000
    flow: xtls-rprx-vision
    tls:
      enabled: true
      server_name: www.example.com
      reality:
        enabled: true
        public_key: publicKeyValue
        short_id: abcd1234
      utls:
        enabled: true
        fingerprint: chrome
    alpn: [h2, http/1.1]
  - name: Nested TLS without Reality
    type: vless
    server: tls.example.com
    port: 443
    uuid: 123e4567-e89b-12d3-a456-426614174002
    tls:
      enabled: true
      server_name: tls.example.com
  - name: Missing Reality Key
    type: vless
    server: invalid.example.com
    port: 443
    uuid: 123e4567-e89b-12d3-a456-426614174003
    tls:
      enabled: true
      reality:
        enabled: true
        short_id: missing-key
YAML
vpn_yaml_to_uri "$T/reality.yaml" > "$T/out"
[ "$(wc -l < "$T/out" | tr -d ' ')" = 2 ] || { cat "$T/out"; echo 'FAIL: expected valid Reality and nested TLS nodes'; exit 1; }
grep -Fq 'security=reality' "$T/out"
grep -Fq 'security=tls' "$T/out"
grep -Fq 'sni=www.example.com' "$T/out"
grep -Fq 'pbk=publicKeyValue' "$T/out"
grep -Fq 'sid=abcd1234' "$T/out"
grep -Fq 'fp=chrome' "$T/out"
grep -Fq 'flow=xtls-rprx-vision' "$T/out"
grep -Fq 'alpn=h2,http/1.1' "$T/out"
! grep -Fq 'invalid.example.com' "$T/out" || { echo 'FAIL: Reality without public key was silently downgraded'; exit 1; }
. "$ROOT/scripts/vpncore.sh"
URI=$(grep '^vless://.*security=reality' "$T/out" | head -n1)
OUT=$(singbox_node_outbound "$URI" reality-test)
python3 - "$OUT" <<'PYJSON'
import json,sys
o=json.loads(sys.argv[1])
assert o['tls']['reality']['public_key']=='publicKeyValue',o
assert o['tls']['reality']['short_id']=='abcd1234',o
assert o['tls']['utls']['fingerprint']=='chrome',o
assert o['tls']['alpn']==['h2','http/1.1'],o
assert o['flow']=='xtls-rprx-vision',o
PYJSON
echo 'PASS: Clash Meta Reality fields survive YAML import and sing-box outbound generation'
