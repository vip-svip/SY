#!/bin/sh
# Host-side source-contract tests; not an Android mount/trust test.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
CERT="$ROOT/scripts/certmgr.sh"
python3 - "$CERT" <<'PYTEST'
import sys
s=open(sys.argv[1]).read()
a=s.index('      enable)')
b=s.index('      disable)', a)
e=s[a:b]
# Existing child directory must not be destroyed before staging succeeds.
assert e.index('rm -rf "$_en_dest"') > e.index('mv "$_en_stage" "$_en_dest"')
assert '_en_stage="$SM/.$id.enable-stage.$$"' in e
assert '_en_prev="$SM/.$id.enable-prev.$$"' in e
assert e.index('cp "$_en_tmpl/module.prop" "$_en_stage/module.prop"') < e.index('mv "$_en_dest" "$_en_prev"')
assert e.index('mv "$_en_dest" "$_en_prev"') < e.index('mv "$_en_stage" "$_en_dest"')
assert 'grep -q \'^version=\' "$_en_stage/module.prop"' in e
assert 'set -- "$_en_stage/system/etc/security/cacerts/"*.0' in e
# Publication and trust-sync failures attempt exact prior-directory restoration.
assert 'enable rollback could not restore previous submodule' in e
assert 'enable rollback resync still incomplete' in e
assert '[ "$_en_had_optin" = 1 ] || rm -f "$PG/ca-trust-optin"' in e
assert 'rm -rf "$_en_prev" 2>/dev/null' in e
# Removed submodule marker is retained in the previous directory until publish succeeds.
assert 'Never delete an' in e and 'existing remove marker until the replacement is complete and publishable.' in e
PYTEST
# Historical regressions run independently by the suite driver; avoid nested execution.
find "$ROOT/scripts" -type f -name '*.sh' -exec sh -n {} \;
test -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop"
test -f "$ROOT/certs/submodules/pg_https_ca/module.prop"
echo 'PASS: certificate enable staging/publish/rollback source contracts, certificate source contracts, shell syntax, independent certificate submodules'
