#!/bin/sh
# Verify certificate status fallback works without openssl and CA hash collisions never overwrite stock entries.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Collision-safe copy/removal operates only on this test fixture.
. "$ROOT/scripts/certcopy.sh"
mkdir -p "$TMP/src" "$TMP/store"
printf 'custom-ca-data\n' > "$TMP/src/deadbeef.0"
printf 'stock-root-zero\n' > "$TMP/store/deadbeef.0"
printf 'stock-root-one\n' > "$TMP/store/deadbeef.1"
ca_copy_submodule_certs "$TMP/src" "$TMP/store" collision-test
[ "$(cat "$TMP/store/deadbeef.0")" = stock-root-zero ]
[ "$(cat "$TMP/store/deadbeef.1")" = stock-root-one ]
[ "$(cat "$TMP/store/deadbeef.2")" = custom-ca-data ]
# Repeated sync must not add another duplicate copy.
ca_copy_submodule_certs "$TMP/src" "$TMP/store" collision-test
[ "$(cat "$TMP/store/deadbeef.2")" = custom-ca-data ]
[ ! -e "$TMP/store/deadbeef.3" ]
ca_remove_submodule_certs "$TMP/src" "$TMP/store" collision-test
[ "$(cat "$TMP/store/deadbeef.0")" = stock-root-zero ]
[ "$(cat "$TMP/store/deadbeef.1")" = stock-root-one ]
[ ! -e "$TMP/store/deadbeef.2" ]

# If the FX certificate temporarily occupied .0 and a different certificate was
# retained at .1, removal compacts the original collision chain without deleting it.
mkdir -p "$TMP/src2" "$TMP/store2"
printf 'fx-ca\n' > "$TMP/src2/cafebabe.0"
printf 'fx-ca\n' > "$TMP/store2/cafebabe.0"
printf 'stock-ca\n' > "$TMP/store2/cafebabe.1"
ca_remove_submodule_certs "$TMP/src2" "$TMP/store2" collision-test
[ "$(cat "$TMP/store2/cafebabe.0")" = stock-ca ]
[ ! -e "$TMP/store2/cafebabe.1" ]

# Run the real certmgr list code with openssl intentionally absent from PATH.
MOD="$TMP/mod"; SM="$TMP/modules"; SC="$TMP/system/cacerts"; PG="$TMP/pg"
mkdir -p "$MOD/scripts" "$MOD/certs/submodules" "$SM/pg_mitm_ca/system/etc/security/cacerts" "$SC" "$PG" "$TMP/bin"
cp "$ROOT/scripts/certmgr.sh" "$ROOT/scripts/certcopy.sh" "$ROOT/scripts/certmarker.sh" "$ROOT/scripts/cert-apex-ns.sh" "$MOD/scripts/"
cp -R "$ROOT/certs/ca-index" "$ROOT/certs/submodules" "$MOD/certs/"
cp "$ROOT/certs/submodules/pg_mitm_ca/module.prop" "$SM/pg_mitm_ca/module.prop"
cp "$ROOT/certs/submodules/pg_mitm_ca/system/etc/security/cacerts/"*.0 "$SM/pg_mitm_ca/system/etc/security/cacerts/"
cp "$ROOT/certs/submodules/pg_mitm_ca/system/etc/security/cacerts/"*.0 "$SC/"
# The source copy is patched to use isolated paths and to treat APEX as absent.
sed -i \
  -e "s|^SM=/data/adb/modules$|SM=$SM|" \
  -e "s|^SC=/system/etc/security/cacerts$|SC=$SC|" \
  -e "s|^PG=/data/adb/privacyguard$|PG=$PG|" \
  -e "s|^MDIR_CERTS=/data/adb/modules/privacyguard/certs$|MDIR_CERTS=$MOD/certs|" \
  -e 's|^SC_APEX=.*|SC_APEX=|' "$MOD/scripts/certmgr.sh"
# A restricted PATH keeps the real required utilities but intentionally omits openssl.
for cmd in base64 sha256sum sed grep tr cut dirname ls head awk find wc cat readlink cmp rm mkdir chmod; do
  src=$(command -v "$cmd")
  ln -s "$src" "$TMP/bin/$cmd"
done
out=$(PATH="$TMP/bin" /bin/sh "$MOD/scripts/certmgr.sh" builtin list 2>"$TMP/stderr") || {
  cat "$TMP/stderr" >&2; echo 'FAIL certmgr list failed without openssl' >&2; exit 1;
}
printf '%s\n' "$out" | grep -Fq '"system":1' || { echo 'FAIL certificate fingerprint was not verified without openssl' >&2; printf '%s\n' "$out" >&2; cat "$TMP/stderr" >&2; exit 1; }
! grep -Fq 'not found' "$TMP/stderr" || { echo 'FAIL external openssl remained required' >&2; cat "$TMP/stderr" >&2; exit 1; }

echo 'PASS: collision-safe CA slots, idempotent add/remove, and certmgr fingerprint fallback without openssl'
