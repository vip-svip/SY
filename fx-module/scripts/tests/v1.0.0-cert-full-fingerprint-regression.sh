#!/bin/sh
# Trust decisions must compare the full DER SHA-256, never the 16-hex index prefix.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CERT="$ROOT/scripts/certmgr.sh"
NS="$ROOT/scripts/cert-apex-ns.sh"
TMP=${TMPDIR:-/tmp}/fx-cert-full-fp-$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP"
sed -n '/^ca_fp256() {/,/^}/p; /^ca_file_matches256() {/,/^}/p' "$CERT" > "$TMP/functions.sh"
[ -s "$TMP/functions.sh" ] || { echo 'FAIL: full fingerprint functions missing' >&2; exit 1; }
. "$TMP/functions.sh"
export TMPDIR="$TMP"
PG="$TMP/pg"; mkdir -p "$PG"; chmod 700 "$PG"; export PG
A="$ROOT/certs/pg-mitm-ca.pem"
B="$ROOT/certs/pg-https-ca.pem"
A256=$(ca_fp256 "$A") || { echo 'FAIL: could not fingerprint CA A' >&2; exit 1; }
B256=$(ca_fp256 "$B") || { echo 'FAIL: could not fingerprint CA B' >&2; exit 1; }
[ "${#A256}" -eq 64 ] || { echo 'FAIL: SHA-256 fingerprint is not 256-bit hex' >&2; exit 1; }
[ "${#B256}" -eq 64 ] || { echo 'FAIL: second fingerprint is not 256-bit hex' >&2; exit 1; }
[ "$A256" != "$B256" ] || { echo 'FAIL: distinct CA files got same digest' >&2; exit 1; }
ca_file_matches256 "$A" "$A256" || { echo 'FAIL: matching CA rejected' >&2; exit 1; }
if ca_file_matches256 "$B" "$A256"; then echo 'FAIL: unrelated CA accepted as trusted' >&2; exit 1; fi
if ca_file_matches256 "$A" "${A256%????????????????????????????????????????????????}"; then
  echo 'FAIL: compact/truncated fingerprint accepted for trust' >&2; exit 1
fi
printf '%s\n' 'not a PEM certificate' > "$TMP/invalid.pem"
if ca_fp256 "$TMP/invalid.pem" >/dev/null 2>&1; then
  echo 'FAIL: malformed certificate fingerprint accepted' >&2; exit 1
fi
python3 - "$CERT" "$NS" <<'PY'
import sys
c=open(sys.argv[1],encoding='utf-8').read()
n=open(sys.argv[2],encoding='utf-8').read()
assert 'ca_file_matches256 "$_csh_dir/$_csh_hash.$_csh_n" "$_csh_fp256"' in c
assert 'ca_store_has_cert "$SC_APEX" "$_ca_h1" "$_ca_h2" "$_ca_fp256"' in c
assert 'ca_store_has_cert "$SC" "$_cs_h1" "$_cs_h2" "$_cs_fp256"' in c
assert 'ca_apex_ns_verify_zygote "$SC_APEX" "$_ls_fp256" "$H1" "$H2"' in c
assert 'ca_file_matches256 "/proc/$_cav_pid/root$_cav_target/$_cav_hash.$_cav_n" "$_cav_fp256"' in n
assert '[ "${#_cav_fp256}" -eq 64 ] || return 1' in n
PY
sh -n "$CERT"
sh -n "$NS"
echo 'PASS: full 256-bit CA fingerprints gate system/APEX/zygote trust decisions'
