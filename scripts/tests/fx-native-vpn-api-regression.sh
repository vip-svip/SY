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
! grep -Fq "document.getElementById('vpnEnableToggle');if(b)b.click()" "$ACTIVITY" || fail "native switch still clicks hidden legacy WebUI toggle"
! grep -Fq "querySelectorAll('#vpnModeSeg > *')" "$ACTIVITY" || fail "native mode selector still clicks hidden legacy WebUI controls"
echo "FX explicit native VPN API regression: PASS"
