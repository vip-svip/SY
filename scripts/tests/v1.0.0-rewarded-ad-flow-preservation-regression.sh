#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SRC="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SRC" ] || fail 'API101 AdVisibilityHook.java missing'
grep -q 'REWARDED_FLOW_MARKERS' "$SRC" || fail 'rewarded-flow markers missing'
grep -q 'isRewardedFlowEvidence(evidence)' "$SRC" || fail 'rewarded class/resource evidence gate missing'
grep -q 'containsRewardedText(view, 3, new int\[\]{MAX_REWARDED_AD_SUBTREE_NODES})' "$SRC" || fail 'bounded rewarded CTA descendant scan missing'
grep -q 'MAX_REWARDED_AD_SUBTREE_NODES = 64' "$SRC" || fail 'rewarded CTA scan must be bounded'
grep -q 'server-validation path' "$SRC" || fail 'provider-owned reward validation guarantee missing'
if grep -E 'onRewarded[^;]*(setResult|grant\(|return true)' "$SRC"; then fail 'reward callback mutation detected'; fi
echo 'FX rewarded-ad flow preservation regression: PASS'
