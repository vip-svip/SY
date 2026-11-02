#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="${1:-$ROOT/fx-module/webroot/index.html}"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HTML" ] || fail "canonical FX WebUI is missing"
grep -Fq 'window.FXNativeVpn={snapshot:state,setEnabled:setEnabled,setMode:setMode,selectNode:selectNode};' "$HTML" || fail "explicit native VPN API missing"
grep -Fq 'applyVpnModeSelection(String(mode||\x27\x27))' "$HTML" || grep -Fq "applyVpnModeSelection(String(mode||''))" "$HTML" || fail "native API does not call validated mode transaction"
grep -Fq 'function selectNode(index)' "$HTML" || fail "native node selection API missing"
grep -Fq 'Promise.resolve(pgPersistNow())' "$HTML" || fail "native node selection does not await config persistence"
grep -Fq 'liveKnown:window.__pgVpnLiveKnown===true' "$HTML" || fail "native state snapshot omits backend-confirmed live state"
grep -Fq 'private void syncNativeVpnControls()' "$ACTIVITY" || fail "native VPN state synchronization missing"
grep -Fq 'private void showNativeVpnNodePicker()' "$ACTIVITY" || fail "native node picker is missing"
grep -Fq 'invokeNativeVpnApi("setMode"' "$ACTIVITY" || fail "native mode controls are not wired to the explicit API"
grep -Fq 'invokeNativeVpnApi("setEnabled"' "$ACTIVITY" || fail "native master switch is not wired to the explicit API"
grep -Fq 'setThumbTintList' "$ACTIVITY" || fail "native VPN switch thumb is not explicitly white"
grep -Fq 'setTrackTintList' "$ACTIVITY" || fail "native VPN switch track is not transparent-tinted"
! grep -Fq 'vpnEnableToggle' "$ACTIVITY" || fail "native switch still references hidden legacy WebUI toggle"
! grep -Fq 'vpnModeSeg' "$ACTIVITY" || fail "native mode selector still references hidden legacy WebUI controls"
echo "FX explicit native VPN API regression: PASS"
