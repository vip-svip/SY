#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
HTML="$ROOT/webroot/index.html"
NATIVE_UI="$ROOT/../adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail() { echo "FAIL: $*" >&2; exit 1; }
# Large lists must yield to the browser instead of continuously queueing zero-delay work.
grep -Fq 'requestIdleCallback(step,{timeout:240})' "$HTML" || fail 'rule-list renderer does not use idle scheduling'
grep -Fq 'else setTimeout(step,16)' "$HTML" || fail 'fallback renderer does not yield between frames'
grep -Fq 'emit(total<=60?total:40)' "$HTML" || fail 'initial rule-list render batch is too large'
grep -Fq 'chunks>=3||now()-t0>=7' "$HTML" || fail 'rule-list render task has no short time/batch budget'
# Avoid repainting every offscreen list row at full cost on narrow/mobile WebViews.
grep -Fq 'content-visibility:auto;contain-intrinsic-size:auto 52px' "$HTML" || fail 'offscreen list paint containment missing'
grep -Fq 'backdrop-filter:blur(6px) saturate(1.08)!important' "$HTML" || fail 'mobile glass compositing profile missing'
# Debounce VPN node search to prevent a full list rebuild on each keystroke.
grep -Fq 'vpnSearchTimer=setTimeout(function(){vpnSearchTimer=null;renderNodes()},120)' "$HTML" || fail 'VPN node search debounce missing'
grep -Fq 'VPN_NODE_RENDER_GEN++' "$HTML" || fail 'stale progressive VPN renders are not invalidated'
# Hook app selection is native: async loading is generation-guarded and rows are paginated.
grep -Fq 'MAX_APP_ROWS_PER_PAGE = 40' "$NATIVE_UI" || fail 'native Hook page size is not bounded'
grep -Fq 'appLoadGeneration' "$NATIVE_UI" || fail 'native Hook app loader generation missing'
grep -Fq 'generation != appLoadGeneration' "$NATIVE_UI" || fail 'stale native app-list results are not discarded'
grep -Fq 'while (content.getChildCount() > 5) content.removeViewAt(5)' "$NATIVE_UI" || fail 'native Hook list rerender does not preserve fixed controls'
grep -Fq '加载更多应用' "$NATIVE_UI" || fail 'native Hook app list pagination missing'
grep -Fq 'return size() > 80' "$NATIVE_UI" || fail 'native Hook icon cache is not bounded'
grep -Fq 'private void loadMissingAppIconsAsync()' "$NATIVE_UI" || fail 'native Hook icons are not decoded asynchronously'
if sed -n '/private void appendAppRows/,/private void loadMissingAppIconsAsync/p' "$NATIVE_UI" | grep -q 'getApplicationIcon'; then fail 'native Hook app rows decode icons on the UI thread'; fi
grep -Fq 'appIconLoadGeneration' "$NATIVE_UI" || fail 'stale native icon results are not generation-guarded'
grep -Fq 'new Thread(() -> {' "$NATIVE_UI" || fail 'native Hook app index is not loaded asynchronously' 
# UI preference serialization and localStorage writes are deferred/coalesced.
grep -Fq 'function saveStateNow()' "$HTML" || fail 'deferred state writer missing'
grep -Fq 'setTimeout(function(){saveStateTimer=null;saveStateNow()},180)' "$HTML" || fail 'preference writes are not coalesced'
grep -Fq "window.addEventListener('pagehide'" "$HTML" || fail 'pending preference writes not flushed on pagehide'
echo 'PASS: progressive rule/Hook rendering, idle scheduling, offscreen paint containment, mobile compositing reduction, VPN-search debounce and coalesced preference writes verified'
