#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d /tmp/fx-yaml-comment.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/profiles.yaml" <<'YAML'
proxies:
  - name: "Tokyo #1 & test" # display label
    type: vless # protocol
    server: edge.example.com # endpoint
    port: 443 # tls port
    uuid: 123e4567-e89b-12d3-a456-426614174000 # client id
    tls: true # enabled
    servername: "sni.example.com # still data" # comment
YAML
vpn_yaml_to_uri "$T/profiles.yaml" > "$T/out"
grep -Fq 'vless://123e4567-e89b-12d3-a456-426614174000@edge.example.com:443?encryption=none&security=tls' "$T/out"
grep -Fq 'Tokyo%20%231%20%26%20test' "$T/out"
grep -Fq 'sni=sni.example.com%20%23%20still%20data' "$T/out"
! grep -q 'endpoint\|client id\|tls port\|display label' "$T/out"
echo 'PASS: Clash YAML trailing comments are stripped without corrupting quoted # values'
