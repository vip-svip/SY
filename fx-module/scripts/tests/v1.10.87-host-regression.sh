#!/bin/sh
# Host fault-injection for interrupted certificate enable publication; not Android mount tests.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CERT="$ROOT/scripts/certmgr.sh"
TMP=${TMPDIR:-/tmp}/pg-cert-recovery-test.$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/extract" "$TMP/sm"
python3 - "$CERT" "$TMP/recovery.sh" <<'PY'
import sys
s=open(sys.argv[1]).read(); a=s.index('pg_cert_recover_enable_transactions() {'); b=s.index('\n}\n\n# 统一入口',a)+2
open(sys.argv[2],'w').write(s[a:b]+'\n')
PY
PG_CERT_RECOVERY_CHANGED=0
. "$TMP/recovery.sh"
# Crash after old directory moved aside, before new directory is published.
mkdir -p "$TMP/sm/.pg_mitm_ca.enable-prev.123"
printf 'id=pg_mitm_ca\nversion=old\n' > "$TMP/sm/.pg_mitm_ca.enable-prev.123/module.prop"
: > "$TMP/sm/.pg_mitm_ca.enable-prev.123/remove"
mkdir -p "$TMP/sm/.pg_mitm_ca.enable-stage.123"
printf 'id=pg_mitm_ca\nversion=stage\n' > "$TMP/sm/.pg_mitm_ca.enable-stage.123/module.prop"
pg_cert_recover_enable_transactions "$TMP/sm"
grep -q '^version=old$' "$TMP/sm/pg_mitm_ca/module.prop"
test "$PG_CERT_RECOVERY_CHANGED" = 1
test -f "$TMP/sm/pg_mitm_ca/remove"
test ! -e "$TMP/sm/.pg_mitm_ca.enable-stage.123"
# Crash after new directory publication but before transaction cleanup: restore old and quarantine new.
mkdir -p "$TMP/sm/.pg_https_ca.enable-prev.456" "$TMP/sm/pg_https_ca"
printf 'id=pg_https_ca\nversion=old\n' > "$TMP/sm/.pg_https_ca.enable-prev.456/module.prop"
printf 'id=pg_https_ca\nversion=new\n' > "$TMP/sm/pg_https_ca/module.prop"
pg_cert_recover_enable_transactions "$TMP/sm"
grep -q '^version=old$' "$TMP/sm/pg_https_ca/module.prop"
test "$PG_CERT_RECOVERY_CHANGED" = 1
find "$TMP/sm" -maxdepth 1 -type d -name '.pg_https_ca.enable-interrupted.*' | grep -q .
# Idempotent second recovery must not change the restored state.
pg_cert_recover_enable_transactions "$TMP/sm"
grep -q '^version=old$' "$TMP/sm/pg_https_ca/module.prop"
# Invalid snapshot is retained and fails closed.
mkdir -p "$TMP/sm/.pg_mitm_ca.enable-prev.bad"
printf 'id=wrong\nversion=x\n' > "$TMP/sm/.pg_mitm_ca.enable-prev.bad/module.prop"
if pg_cert_recover_enable_transactions "$TMP/sm" 2>/dev/null; then echo 'invalid snapshot unexpectedly accepted' >&2; exit 1; fi
test -d "$TMP/sm/.pg_mitm_ca.enable-prev.bad"
find "$ROOT/scripts" -type f -name '*.sh' -exec sh -n {} \;
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
echo 'PASS: interrupted certificate enable recovery fault injection, idempotence, invalid-snapshot fail-closed, shell syntax, independent cert submodules'
