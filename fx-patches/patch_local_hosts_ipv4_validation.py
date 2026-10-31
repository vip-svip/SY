#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
apply = root / "scripts/apply.sh"
s = apply.read_text(encoding="utf-8")
old = """    if awk '
      { sub(/\\r$/, "") }
"""
new = """    awk '
      function valid_ipv4(ip, parts, n, i) {
        n = split(ip, parts, ".")
        if (n != 4) return 0
        for (i = 1; i <= 4; i++) {
          if (parts[i] !~ /^[0-9]+$/ || length(parts[i]) > 3 || (parts[i] + 0) > 255) return 0
        }
        return 1
      }
      { sub(/\\r$/, "") }
"""
if s.count(old) != 1:
    if "function valid_ipv4(ip, parts, n, i)" in s:
        print("Local hosts IPv4 validation already present.")
        raise SystemExit(0)
    raise SystemExit("local hosts awk start anchor changed or ambiguous")
s = s.replace(old, new, 1)
old2 = "        if (NF >= 2 && $1 ~ /^[0-9.]+$/) { print $0; next }"
new2 = "        if (NF >= 2 && $1 ~ /^[0-9.]+$/) { if (valid_ipv4($1)) print $0; next }"
if s.count(old2) != 1:
    raise SystemExit("local hosts IPv4 acceptance anchor changed or ambiguous")
apply.write_text(s.replace(old2, new2, 1), encoding="utf-8")
test = root / "scripts/tests/v1.0.0-local-hosts-ipv4-validation-regression.sh"
test_text = r'''#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
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
! grep -Eq 'invalid-(high|short|long|range)\\.example' "$T/output"
grep -Fxq '0.0.0.0 localhost' "$T/output"
echo 'FX local hosts IPv4 validation regression: PASS'
'''
test.write_text(test_text, encoding="utf-8")
test.chmod(0o755)
print("Added strict IPv4 validation and runtime regression.")
