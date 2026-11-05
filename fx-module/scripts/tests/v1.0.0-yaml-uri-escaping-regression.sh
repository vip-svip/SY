#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-yaml-uri.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/edge.yaml" <<'YAML'
proxies:
  - name: "Tokyo #1 & test"
    type: vless
    server: 2001:db8::1
    port: 443
    uuid: "id@with:delimiters"
    network: ws
    path: "/a b?c#d"
    servername: "sni.example?x y+z=a&b;c"
  - name: "Trojan auth edge"
    type: trojan
    server: auth.example.com
    port: 443
    password: "p?x&y+z=a/b;c%"
    sni: "tls.example+name=value;part"
YAML
vpn_yaml_to_uri "$T/edge.yaml" > "$T/out"
grep -Fq 'vless://id%40with%3Adelimiters@[2001:db8::1]:443' "$T/out"
grep -Fq 'Tokyo%20%231%20%26%20test' "$T/out"
grep -Fq 'path=/a%20b%3Fc%23d' "$T/out"
grep -Fq 'sni=sni.example%3Fx%20y%2Bz%3Da%26b%3Bc' "$T/out"
grep -Fq 'trojan://p%3Fx%26y%2Bz%3Da%2Fb%3Bc%25@auth.example.com:443?sni=tls.example%2Bname%3Dvalue%3Bpart#Trojan%20auth%20edge' "$T/out"
echo 'PASS: YAML URI IPv6 authority and reserved-character encoding'
