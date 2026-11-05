#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
# Check that both independent builders preserve IPv4 and valid IPv6 address mappings
# before they fall through to the bare-domain-to-0.0.0.0 conversion.
for f in "$ROOT/scripts/util.sh" "$ROOT/scripts/apply.sh"; do
  grep -Fq 'NF >= 2 && $1 ~ /^[0-9.]+$/' "$f" || { echo "FAIL: IPv4 mappings missing in $f" >&2; exit 1; }
  grep -Fq 'NF >= 2 && index($1, ":") > 0 && $1 ~ /^[0-9A-Fa-f:.]+$/' "$f" || { echo "FAIL: IPv6 mappings missing in $f" >&2; exit 1; }
done
# Runtime path test: FX-only hosts builder must emit mappings and still convert bare domains.
sh "$ROOT/scripts/tests/v1.0.0-fx-bundled-source-lifecycle-regression.sh"
echo 'PASS: full and FX-only local hosts builders retain valid IPv4/IPv6 mappings'
