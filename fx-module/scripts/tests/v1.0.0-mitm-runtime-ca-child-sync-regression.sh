#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/fx-mitm-child-sync-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
command -v openssl >/dev/null 2>&1 || { echo 'SKIP: openssl not available for generated runtime CA fixture'; exit 0; }
mkdir -p "$TMP/fixture"
# Generate a different keypair but the exact CA subject expected by init-ca.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -subj '/C=CN/O=PrivacyGuard Project/CN=PrivacyGuard MITM Detection CA' \
  -keyout "$TMP/fixture/runtime.key" -out "$TMP/fixture/runtime.pem" >/dev/null 2>&1
run_case() {
  mode=$1
  base="$TMP/$mode"
  mod="$base/mod"
  pg="$base/pg"
  child="$base/modules/pg_mitm_ca"
  mkdir -p "$mod/scripts" "$mod/bin/arm64" "$pg" "$base/modules"
  cp "$ROOT/module.prop" "$mod/module.prop"
  cp -R "$ROOT/certs" "$mod/certs"
  cp "$TMP/fixture/runtime.pem" "$mod/certs/test-runtime-ca.pem"
  cp "$ROOT/scripts/mitm-engine.sh" "$mod/scripts/mitm-engine.sh"
  # Redirect only the copied script's device paths into the isolated test tree.
  sed -i "s|^PG=/data/adb/privacyguard$|PG=$pg|; s|^CHILD=\"/data/adb/modules/pg_mitm_ca\"$|CHILD=\"$child\"|" "$mod/scripts/mitm-engine.sh"
  cat > "$mod/bin/arm64/pg-mitm" <<'BIN'
#!/bin/sh
out=''
while [ $# -gt 0 ]; do
  case "$1" in -dir) out=$2; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] || exit 2
mkdir -p "$out" || exit 1
cp "$PG_MODDIR/certs/test-runtime-ca.pem" "$out/ca.pem" || exit 1
echo '{"ok":true,"status":"initialized"}'
BIN
  chmod 755 "$mod/bin/arm64/pg-mitm"
  cat > "$mod/scripts/certmgr.sh" <<'CERTMGR'
#!/system/bin/sh
case "$1:$2" in
  builtin:enable)
    if [ ! -d "$MITM_TEST_CHILD" ] || [ -f "$MITM_TEST_CHILD/remove" ]; then
      rm -rf "$MITM_TEST_CHILD"
      cp -R "$MITM_TEST_MODDIR/certs/submodules/pg_mitm_ca" "$MITM_TEST_CHILD" || exit 1
    fi
    rm -f "$MITM_TEST_CHILD/disable" "$MITM_TEST_CHILD/remove"
    n=0
    for f in "$MITM_TEST_CHILD/system/etc/security/cacerts/"*.0; do
      [ -f "$f" ] || continue
      cmp -s "$f" "$MITM_TEST_PG/mitm/ca.pem" || { echo "child certificate mismatch: $f" >&2; exit 1; }
      n=$((n+1))
    done
    [ "$n" -ge 1 ] || { echo 'child certificate missing' >&2; exit 1; }
    echo '{"ok":true,"detail":"test child matches runtime CA"}'
    ;;
  builtin:sync) echo '{"ok":true,"detail":"test sync"}' ;;
  *) echo '{"ok":false,"detail":"unexpected certmgr call"}' >&2; exit 2 ;;
esac
CERTMGR
  chmod 755 "$mod/scripts/certmgr.sh"
  if [ "$mode" = existing-child ]; then
    cp -R "$mod/certs/submodules/pg_mitm_ca" "$child"
  fi
  # Run the actual lifecycle script with only the engine executable/certmgr mocked.
  PG_MODDIR="$mod" MITM_TEST_MODDIR="$mod" MITM_TEST_PG="$pg" MITM_TEST_CHILD="$child" \
    sh "$mod/scripts/mitm-engine.sh" trust-ca > "$base/out.log" 2>&1 || {
      cat "$base/out.log" >&2
      echo "FAIL: trust-ca failed for $mode" >&2
      return 1
    }
  [ -d "$child/system/etc/security/cacerts" ] || { cat "$base/out.log" >&2; echo "FAIL: child module not created for $mode" >&2; return 1; }
  n=0
  for f in "$child/system/etc/security/cacerts/"*.0; do
    [ -f "$f" ] || continue
    cmp -s "$f" "$pg/mitm/ca.pem" || { echo "FAIL: child certificate does not match runtime CA for $mode ($f)" >&2; return 1; }
    n=$((n+1))
  done
  [ "$n" -ge 1 ] || { echo "FAIL: no child CA files for $mode" >&2; return 1; }
  [ ! -e "$pg/mitm/trust-backup" ] || { echo "FAIL: trust backup not cleaned after commit for $mode" >&2; return 1; }
}
run_case existing-child
run_case missing-child
echo 'MITM runtime CA child-module synchronization regression: PASS'
