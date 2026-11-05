#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
[ "$(sed -n 's/^name=//p' "$ROOT/module.prop" | head -1)" = "FX" ]
[ "$(sed -n 's/^version=//p' "$ROOT/module.prop" | head -1)" = "1.0.0" ]
# Keep the internal ID stable to preserve upgrade-in-place behavior.
[ "$(sed -n 's/^id=//p' "$ROOT/module.prop" | head -1)" = "privacyguard" ]
[ -f "$ROOT/certs/submodules/pg_mitm_ca/module.prop" ]
[ -f "$ROOT/certs/submodules/pg_https_ca/module.prop" ]
echo 'FX branding regression: PASS'
