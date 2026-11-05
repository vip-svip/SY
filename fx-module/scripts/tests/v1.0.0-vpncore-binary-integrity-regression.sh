#!/bin/sh
# Same-size corrupt persistent binaries must be repaired from the verified bundled core.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
MOD="$T/module"; PG="$T/pg"
mkdir -p "$MOD/bin/arm64" "$PG/bin"
printf '%s\n' 'fake-sing-box-source-content-A' > "$MOD/bin/arm64/sing-box"
chmod 755 "$MOD/bin/arm64/sing-box"
sha256sum "$MOD/bin/arm64/sing-box" | awk '{print $1 "  sing-box"}' > "$MOD/bin/arm64/sing-box.sha256"
# Same size, different contents reproduces the old size-only acceptance bug.
printf '%s\n' 'fake-sing-box-corrupt-content-B' > "$PG/bin/sing-box"
chmod 755 "$PG/bin/sing-box"
MODDIR="$MOD" PG="$PG" sh -c '
  . "$1"
  vpncore_arch(){ echo arm64; }
  vpncore_moddir(){ echo "$MODDIR"; }
  vpncore_bin(){ echo "$PG/bin/sing-box"; }
  pg_log(){ :; }
  pg_fail(){ echo "$2" >&2; return 1; }
  vpncore_install_builtin
' sh "$ROOT/scripts/vpncore.sh"
expected=$(sha256sum "$MOD/bin/arm64/sing-box" | awk '{print $1}')
actual=$(sha256sum "$PG/bin/sing-box" | awk '{print $1}')
[ "$expected" = "$actual" ] || { echo 'FAIL: same-size corrupt core was not repaired'; exit 1; }
# A corrupt bundled binary with a stale sidecar must be rejected, not copied.
printf '%s\n' 'different-bundled-content' > "$MOD/bin/arm64/sing-box"
if MODDIR="$MOD" PG="$PG" sh -c '
  . "$1"
  vpncore_arch(){ echo arm64; }
  vpncore_moddir(){ echo "$MODDIR"; }
  vpncore_bin(){ echo "$PG/bin/sing-box"; }
  pg_log(){ :; }
  pg_fail(){ return 1; }
  vpncore_install_builtin
' sh "$ROOT/scripts/vpncore.sh" >/dev/null 2>&1; then
  echo 'FAIL: corrupt bundled core with stale checksum was accepted'; exit 1
fi
[ "$(sha256sum "$PG/bin/sing-box" | awk '{print $1}')" = "$expected" ] || { echo 'FAIL: failed source verification damaged installed core'; exit 1; }
echo 'FX VPN core binary integrity regression: PASS'
