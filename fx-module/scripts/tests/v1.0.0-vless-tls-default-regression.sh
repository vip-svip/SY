#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-vless-tls.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
MODDIR="$ROOT" PG="$T/state"; export MODDIR PG
mkdir -p "$PG/cache"
. "$ROOT/scripts/vpnsub.sh"
cat > "$T/profiles.yaml" <<'YAML'
proxies:
  - name: omitted-tls
    type: vless
    server: 192.0.2.1
    port: 443
    uuid: 00000000-0000-0000-0000-000000000001
  - name: explicit-tls
    type: vless
    server: 192.0.2.2
    port: 443
    uuid: 00000000-0000-0000-0000-000000000002
    tls: true
  - name: explicit-no-tls
    type: vless
    server: 192.0.2.3
    port: 80
    uuid: 00000000-0000-0000-0000-000000000003
    tls: false
YAML
vpn_yaml_to_uri "$T/profiles.yaml" > "$T/out"
grep -Fq 'vless://00000000-0000-0000-0000-000000000001@192.0.2.1:443?encryption=none&security=none' "$T/out"
grep -Fq 'vless://00000000-0000-0000-0000-000000000002@192.0.2.2:443?encryption=none&security=tls' "$T/out"
grep -Fq 'vless://00000000-0000-0000-0000-000000000003@192.0.2.3:80?encryption=none&security=none' "$T/out"
echo 'PASS: VLESS omitted/true/false TLS mapping'
