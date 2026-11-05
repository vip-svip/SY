#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
CONF="$ROOT/scripts/default.conf"
RULE="$ROOT/fxrules/anti_fraud_96110.txt"
[ -s "$RULE" ] || { echo 'FAIL: FX anti-fraud rules missing' >&2; exit 1; }
grep -Fq 'fxfile://anti_fraud_96110|FX 专用反诈中心域名/IP 规则' "$CONF" || { echo 'FAIL: default FX source missing' >&2; exit 1; }
python3 -c 'from pathlib import Path; import sys; s=Path(sys.argv[1]).read_text(); b=s.index("PGB.bootPhase=\x27应用本地配置\x27;"); base=s.index("PGB.lastPersistText=pgSerialize(PGB.model)",b); inject=s.index("if(!_fxHasSource){PGB.model.lists.fx.push",b); persist=s.index("if(PGB.fxSourceBootstrapAdded)",inject); assert base < inject < persist, "FX source must be added after recording old config baseline and then persisted"; assert "FX source registration still pending" in s; print("PASS: missing FX rule registration is persisted on existing installations")' "$HTML"
echo 'PASS: FX bundled source and startup config migration wiring'
