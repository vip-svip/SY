#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HTML="${1:-$ROOT/fx-module/webroot/index.html}"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HTML" ] || fail "canonical FX WebUI is missing"
grep -Fq 'window.FXNativeVpn={snapshot:state,setEnabled:setEnabled,setMode:setMode,selectNode:selectNode};' "$HTML" || fail "explicit native VPN API missing"
grep -Fq 'applyVpnModeSelection(mode)' "$HTML" || fail "native API does not call validated mode transaction"
grep -Fq 'function selectNode(index)' "$HTML" || fail "native node selection API missing"
grep -Fq 'Promise.resolve(pgPersistNow())' "$HTML" || fail "native node selection does not await config persistence"
grep -Fq 'liveKnown:window.__pgVpnLiveKnown===true' "$HTML" || fail "native state snapshot omits backend-confirmed live state"
grep -Fq "window.__pgVpnLiveKnown=!!s;window.__pgVpnLiveOn=!!(s&&(s.vpn_on===true||s.vpn_on===1))" "$HTML" || fail "WebUI live-state patch is missing from standalone/native build"
grep -Fq 'window.__vpnFillStatus=function(status)' "$HTML" || fail "native API does not bridge the actual status.sh callback"
grep -Fq "typeof status.vpn_on!=='undefined'" "$HTML" || fail "native API does not use status.sh vpn_on"
grep -Fq 'window.vpnStatus();' "$HTML" || fail "native API does not request a backend status refresh"
grep -Fq '  refreshRuntimeStatus();' "$HTML" || fail "native VPN state is not primed at WebView startup"
grep -Fq 'window.__fxNativeVpnBusy=true' "$HTML" || fail "native API lacks operation serialization"
grep -Fq 'window.__fxNativeVpnLastError' "$HTML" || fail "native API does not expose operation failure"
grep -Fq 'return Promise.resolve(pgPersistNow())' "$HTML" || fail "node rollback does not persist the previous node"
grep -Fq 'private void syncNativeVpnControls()' "$ACTIVITY" || fail "native VPN state synchronization missing"
grep -Fq 'RootAccess.execute(nativeVpnRootCommand("status", "")' "$ACTIVITY" || fail "native VPN status is not read from the root backend"
grep -Fq 'sh \"$MP/scripts/status.sh\"' "$ACTIVITY" || fail "native VPN status command does not call status.sh"
grep -Fq 'sh \"$MP/scripts/apply.sh\"' "$ACTIVITY" || fail "native VPN mode/node operations do not apply the module backend"
grep -Fq 'old_mode=$(pg_get vpn_mode direct)' "$ACTIVITY" || fail "native VPN mode change does not snapshot previous mode"
grep -Fq 'pg_set vpn_mode \"$old_mode\"' "$ACTIVITY" || fail "native VPN mode failure does not restore previous mode"
grep -Fq 'old_node=$(pg_get vpn_node' "$ACTIVITY" || fail "native VPN node change does not snapshot previous node"
grep -Fq 'pg_set vpn_node \"$old_node\"' "$ACTIVITY" || fail "native VPN node failure does not restore previous node"
grep -Fq 'if [ -z \"$node\" ]; then pg_set vpn_mode \"$old_mode\" || :;' "$ACTIVITY" || fail "native proxy mode must restore the previous mode when no node is selected"
grep -Fq 'VPN_NO_NODE_SELECTED' "$ACTIVITY" || fail "native proxy mode does not report why no-node apply was rejected"
grep -Fq 'exit 32; fi;' "$ACTIVITY" || fail "native proxy mode does not fail closed without a selected node"
python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
for name, next_name in [
    ("private void invokeNativeVpnApi(", "private void refreshWebUiAfterNativeVpn()"),
    ("private void syncNativeVpnControls()", "private void pauseAndDetachWebView()"),
]:
    start = source.find(name)
    end = source.find(next_name, start + len(name))
    if start < 0 or end < 0:
        raise SystemExit("FAIL: cannot locate native VPN method " + name)
    body = source[start:end]
    if "webView.evaluateJavascript" in body:
        raise SystemExit("FAIL: native VPN control operation/state still depends on WebView JavaScript: " + name)
refresh_start = source.find("private void refreshWebUiAfterNativeVpn()")
refresh_end = source.find("private void showNativeVpnNodePicker()", refresh_start)
if refresh_start < 0 or refresh_end < 0:
    raise SystemExit("FAIL: cannot locate display-only WebView refresh helper")
refresh_body = source[refresh_start:refresh_end]
if "applyVpnModeSelection" in refresh_body or "invokeNativeVpnApi(" in refresh_body:
    raise SystemExit("FAIL: WebView display refresh helper must not execute VPN control actions")
print("FX native VPN Root backend separation: PASS")
PY
grep -Fq 'private void showNativeVpnNodePicker()' "$ACTIVITY" || fail "native node picker is missing"
grep -Fq 'invokeNativeVpnApi("setMode"' "$ACTIVITY" || fail "native mode controls are not wired to the explicit API"
grep -Fq 'invokeNativeVpnApi("setEnabled"' "$ACTIVITY" || fail "native master switch is not wired to the explicit API"
grep -Fq 'setThumbTintList' "$ACTIVITY" || fail "native VPN switch thumb is not explicitly white"
grep -Fq 'setTrackTintList' "$ACTIVITY" || fail "native VPN switch track is not transparent-tinted"
grep -Fq 'nativeVpnHandler.removeCallbacksAndMessages(null)' "$ACTIVITY" || fail "VPN Handler callbacks survive Activity teardown"
grep -Fq 'nativeVpnStatusQueued.compareAndSet(false, true)' "$ACTIVITY" || fail "native VPN status polling can queue unbounded duplicate root jobs"
grep -Fq 'private void refreshWebUiAfterNativeVpn()' "$ACTIVITY" || fail "native VPN updates do not refresh the cached WebUI model"
grep -Fq 'return pgLoad().then(function()' "$ACTIVITY" || fail "native VPN completion does not reload persisted settings for display"
grep -Fq "if(typeof renderNodes==='function')renderNodes();" "$ACTIVITY" || fail "native VPN node selection does not refresh the displayed node list"
grep -Fq 'lastWebTabIndex != 0' "$ACTIVITY" || fail "native VPN polling continues while VPN tab is hidden"
! grep -Fq '}, 1500L);' "$ACTIVITY" || fail "native VPN controls are re-enabled by a timer before Root apply completes"
! grep -Fq "document.getElementById('vpnEnableToggle');if(b)b.click()" "$ACTIVITY" || fail "native switch still clicks hidden legacy WebUI toggle"
! grep -Fq "document.querySelectorAll('#vpnModeSeg > *')" "$ACTIVITY" || fail "native mode selector still clicks hidden legacy WebUI controls"
echo "FX explicit native VPN API regression: PASS"
