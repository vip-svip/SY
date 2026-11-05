#!/bin/sh
# Host-side guard: a candidate FX ZIP must contain the actual KernelSU module entrypoints.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
for f in module.prop customize.sh service.sh post-fs-data.sh uninstall.sh webroot/index.html scripts/apply.sh scripts/util.sh scripts/gen_xposed_conf.sh scripts/vpncore.sh scripts/certmgr.sh; do
  [ -s "$ROOT/$f" ] || fail "required package file missing or empty: $f"
done
# The module metadata must retain the project's fixed release version.
grep -Eq '^version=1\.0\.0[[:space:]]*$' "$ROOT/module.prop" || fail "module version is not fixed at 1.0.0"
# Core executable entrypoints must retain executable bits in the extracted package.
for f in customize.sh service.sh post-fs-data.sh uninstall.sh scripts/apply.sh; do
  [ -x "$ROOT/$f" ] || fail "core entrypoint lost executable permission: $f"
done
# Guard against accidental placeholder UI or a tiny/truncated webroot payload.
[ "$(wc -c < "$ROOT/webroot/index.html" | tr -d ' ')" -gt 100000 ] || fail "webroot/index.html looks truncated or replaced with a placeholder"
echo "PASS: FX 1.0.0 KernelSU package contains required entrypoints, executable modes, and full UI payload"
