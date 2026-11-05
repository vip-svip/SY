#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
U="$ROOT/uninstall.sh"
M="$ROOT/module.prop"
# Version metadata must match the artifact.
grep -Fq 'version=1.0.0' "$M"
grep -Fq 'versionCode=10000' "$M"
# Both certificate cleanup operations must be checked and failures must preserve data.
grep -Fq 'if ! sh "$MODDIR/scripts/certmgr.sh" builtin purge; then' "$U"
grep -Fq 'if ! sh "$MODDIR/scripts/certmgr.sh" cleanup restore; then' "$U"
grep -Fq 'PG_KEEP_DATA=1' "$U"
grep -Fq 'built-in CA submodule purge failed; preserving $PG' "$U"
grep -Fq 'historical certificate quarantine restore failed; preserving $PG' "$U"
# Ensure the prior firewall cleanup guard is retained.
grep -Fq '最多清除 64 条模块自有父链跳转' "$U"
for f in "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/tests/*.sh; do [ ! -f "$f" ] || sh -n "$f"; done
echo 'v1.10.92 host regression: PASS'
