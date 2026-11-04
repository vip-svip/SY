#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallAppFilterPolicy.java"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java"
TEST="$ROOT/scripts/tests/FxYulongFirewallAppFilterPolicyHostTest.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
fail() { echo "FAIL: $*" >&2; exit 1; }
for f in "$POLICY" "$ACTIVITY" "$TEST" "$MAIN"; do
    [ -s "$f" ] || fail "missing Firewall regression source: $f"
done
python3 - "$ACTIVITY" "$MAIN" <<'PY'
from pathlib import Path
import sys
activity, main = [Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]]
assert "FxYulongFirewallAppFilterPolicy.includes(appFilterMode, info.flags)" in activity
assert 'case "用户应用": case "系统应用": case "按应用设置": case "应用网络拦截":' in main
assert '.putExtra("suite_page", page)' in main
assert 'page.equals("用户应用") || page.equals("系统应用") || page.equals("按应用设置")' in main
assert 'page.equals("应用网络拦截")' in main
assert 'button("‹ 返回", this::finish)' in activity
assert "STATE_APP_PAGE" in activity and "STATE_QUERY" in activity and "STATE_SCROLL_Y" in activity
assert "FLAG_UPDATED_SYSTEM_APP" in activity or "FxYulongFirewallAppFilterPolicy" in activity
print("PASS: Firewall route, lifecycle and policy wiring")
PY
command -v javac >/dev/null 2>&1 || fail "JDK is required"
command -v java >/dev/null 2>&1 || fail "JRE is required"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
javac -Xlint:all -Werror -d "$OUT" "$POLICY" "$TEST"
java -cp "$OUT" de.privacyguard.adhook.imported.ad.FxYulongFirewallAppFilterPolicyHostTest
