#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
p = root / "scripts/vpnsub.sh"
s = p.read_text(encoding="utf-8")
if "FX_CLASH_REALITY_FIELDS_V1" not in s:
    replacements = [
        ('function reset(){ typ = ""; name = ""; host = ""; port = ""; id = ""; pw = ""; sni = ""; net = ""; path = ""; tls = ""; cipher = "" }',
         'function reset(){ typ = ""; name = ""; host = ""; port = ""; id = ""; pw = ""; sni = ""; net = ""; path = ""; tls = ""; cipher = ""; flow = ""; fp = ""; pbk = ""; sid = ""; alpn = ""; reality = "" }'),
        ('printf "%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher',
         'printf "%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\037%s\\n", typ, name, host, port, id, pw, sni, net, path, tls, cipher, flow, fp, pbk, sid, alpn, reality'),
        ('else if (k == "tls") tls = tolower(v)',
         'else if (k == "tls") { tls = tolower(v); if (v ~ /enabled:[ \\t]*true/) tls = "true" }\n'
         '  else if (k == "enabled" && tolower(v) == "true") tls = "true"\n'
         '  else if (k == "server_name" || k == "server-name") { if (sni == "") sni = v }\n'
         '  else if (k == "flow") flow = v\n'
         '  else if (k == "fingerprint" || k == "client-fingerprint") fp = v\n'
         '  else if (k == "public-key" || k == "public_key") pbk = v\n'
         '  else if (k == "short-id" || k == "short_id") sid = v\n'
         '  else if (k == "alpn") { gsub(/[\\[\\]\\\" ]/, "", v); alpn = v }\n'
         '  else if (k == "reality" || k == "reality-opts") reality = "1"'),
        ('while IFS="$_yu_sep" read -r _yt _yn _yh _yp _yid _ypw _ysni _ynet _ypath _ytls _yci; do',
         'while IFS="$_yu_sep" read -r _yt _yn _yh _yp _yid _ypw _ysni _ynet _ypath _ytls _yci _yflow _yfp _ypbk _ysid _yalpn _yreality; do'),
        ('      vless)\n        _yv_security=none\n        case "$_ytls" in true|yes|1|tls|enabled) _yv_security=tls ;; esac\n        echo "vless://${_yid_uri}@${_yh}:${_yp}?encryption=none&security=${_yv_security}&sni=${_ysni_uri}&type=${_ynet:-tcp}&path=${_ypath_uri:-/}#${_yn_uri}"',
         '      vless)\n        _yv_security=none\n        case "$_ytls" in true|yes|1|tls|enabled) _yv_security=tls ;; esac\n'
         '        if [ "$_yreality" = "1" ] || [ -n "$_ypbk" ]; then\n'
         '          # Never silently downgrade a Reality profile to ordinary TLS.\n'
         '          [ -n "$_ypbk" ] || continue\n'
         '          _yv_security=reality\n'
         '        fi\n'
         '        _yv_extra=\n'
         '        [ -n "$_ypbk" ] && _yv_extra="$_yv_extra&pbk=$(printf \'%s\' "$_ypbk" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_ysid" ] && _yv_extra="$_yv_extra&sid=$(printf \'%s\' "$_ysid" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_yfp" ] && _yv_extra="$_yv_extra&fp=$(printf \'%s\' "$_yfp" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_yflow" ] && _yv_extra="$_yv_extra&flow=$(printf \'%s\' "$_yflow" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        [ -n "$_yalpn" ] && _yv_extra="$_yv_extra&alpn=$(printf \'%s\' "$_yalpn" | sed \'s/%/%25/g; s/&/%26/g; s/#/%23/g\')"\n'
         '        echo "vless://${_yid_uri}@${_yh}:${_yp}?encryption=none&security=${_yv_security}&sni=${_ysni_uri}&type=${_ynet:-tcp}&path=${_ypath_uri:-/}${_yv_extra}#${_yn_uri}"'),
    ]
    for old, new in replacements:
        if old not in s:
            raise SystemExit("missing vpnsub patch anchor: " + old[:90])
        s = s.replace(old, new, 1)
    anchor = "# Escape a single-line shell value for a JSON string."
    if anchor not in s:
        raise SystemExit("missing vpnsub JSON escape anchor")
    s = s.replace(anchor, "# FX_CLASH_REALITY_FIELDS_V1\n" + anchor, 1)
    p.write_text(s, encoding="utf-8")

test = root / "scripts/tests/v1.0.0-clash-reality-yaml-regression.sh"
test.parent.mkdir(parents=True, exist_ok=True)
test.write_text(r'''#!/system/bin/sh
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
[ "$(wc -l < "$T/out" | tr -d ' ')" = 1 ] || { cat "$T/out"; echo 'FAIL: expected only valid Reality node'; exit 1; }
grep -Fq 'security=reality' "$T/out"
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
''', encoding="utf-8")
test.chmod(0o755)
