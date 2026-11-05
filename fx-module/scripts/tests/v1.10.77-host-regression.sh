#!/bin/sh
# Reproducible host-side regression tests. These do not simulate Android mounts.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
. "$ROOT/scripts/certcopy.sh"
mkdir -p "$TMP/src" "$TMP/dest" "$TMP/bin"
printf 'cert-one\n' > "$TMP/src/11111111.0"
ca_copy_submodule_certs "$TMP/src" "$TMP/dest" test
[ "$(cat "$TMP/dest/11111111.0")" = cert-one ]
# Empty source must fail closed.
mkdir -p "$TMP/empty"
if ca_copy_submodule_certs "$TMP/empty" "$TMP/dest" test-empty 2>/dev/null; then
  echo 'FAIL: empty cert source accepted' >&2; exit 1
fi
# Inject cp failure and verify the helper reports failure, not success.
cat > "$TMP/bin/cp" <<'CP'
#!/bin/sh
exit 73
CP
chmod +x "$TMP/bin/cp"
# A duplicate CA is intentionally a no-op now, so failure injection must use a
# clean destination to guarantee the code reaches the cp/atomic-publish path.
mkdir -p "$TMP/dest-fail"
if PATH="$TMP/bin:$PATH" ca_copy_submodule_certs "$TMP/src" "$TMP/dest-fail" test-fail 2>/dev/null; then
  echo 'FAIL: injected cp failure accepted' >&2; exit 1
fi
# Verify signal handler/lock ordering contracts in production script.
grep -q "trap 'exit 129' HUP" "$ROOT/scripts/apply.sh"
grep -q "trap 'exit 130' INT" "$ROOT/scripts/apply.sh"
grep -q "trap 'exit 143' TERM" "$ROOT/scripts/apply.sh"
python3 - "$ROOT/scripts/apply.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
marker='Keep the apply lock held through rollback'
pos=s.index(marker)
assert s.index('rm -rf "$APPLY_LOCK"',pos) > pos
PY
echo 'PASS: certificate copy success/empty-source/cp-failure injection and transaction trap assertions'
