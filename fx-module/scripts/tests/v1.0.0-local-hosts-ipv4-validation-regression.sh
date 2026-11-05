#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
sh -n "$ROOT/scripts/apply.sh"
T=$(mktemp -d /tmp/fx-local-host-ipv4.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
python3 - "$ROOT/scripts/apply.sh" "$T/local-hosts.awk" <<'PY'
from pathlib import Path
import re, sys
source = Path(sys.argv[1]).read_text()
m = re.search(r"""    if awk '\n(.*?)\n      }' "\$PG/local/hosts" """, source, re.S)
if not m:
    raise SystemExit("FAIL: could not extract local-hosts parser")
Path(sys.argv[2]).write_text("\n".join(line[6:] if line.startswith("      ") else line for line in m.group(1).splitlines()) + "\n}\n")
PY
cat > "$T/input" <<'INPUT'
127.0.0.1 valid.example
255.255.255.255 broadcast.example
256.1.1.1 invalid-high.example
1.2.3 invalid-short.example
1.2.3.4.5 invalid-long.example
999.999.999.999 invalid-range.example
localhost
INPUT
awk -f "$T/local-hosts.awk" "$T/input" > "$T/output"
grep -Fxq '127.0.0.1 valid.example' "$T/output"
grep -Fxq '255.255.255.255 broadcast.example' "$T/output"
! grep -Eq 'invalid-(high|short|long|range)\.example' "$T/output"
grep -Fxq '0.0.0.0 localhost' "$T/output"
echo 'FX local hosts IPv4 validation regression: PASS'
