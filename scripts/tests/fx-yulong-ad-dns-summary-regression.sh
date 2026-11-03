#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HELPER="$ROOT/scripts/yulong-ad-dns-summary.sh"
CONTROL="$ROOT/scripts/yulong-ad-control.sh"
PATCHER="$ROOT/fx-patches/patch_yulong_ad_dns_logs.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HELPER" ] || fail "numeric-only DNS summary helper missing"
if [ -n "${1:-}" ]; then
  [ -s "$1/scripts/yulong-ad-dns-summary.sh" ] || fail "restored module DNS summary helper missing"
  cmp -s "$HELPER" "$1/scripts/yulong-ad-dns-summary.sh" || fail "restored module DNS summary helper differs from canonical source"
fi
sh -n "$HELPER" || fail "DNS summary helper syntax invalid"
sh -n "$CONTROL" || fail "Yulong control script syntax invalid"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-dns-summary.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/data"
cat > "$TMP/data/querylog.json" <<'JSON'
{"QH":"ads.example","QT":"A","IsFiltered":true,"ClientIP":"192.0.2.11"}
{"QH":"open.example","QT":"AAAA","IsFiltered":false,"ClientIP":"192.0.2.12"}
{"QH":"tracker.example","QT":"A","Result":{"IsFiltered":true,"Reason":"FilteredBlackList"},"ClientIP":"192.0.2.13"}
{"question":{"host":"pass.example","type":"A"},"status":"NOERROR","ClientIP":"192.0.2.14"}
JSON
OUT=$(sh "$HELPER" "$TMP/data")
printf '%s\n' "$OUT" | grep -qx 'FXYULONGDNSSTATS1' || fail "summary protocol header missing"
printf '%s\n' "$OUT" | grep -qx 'queries=4' || fail "all DNS query rows were not counted"
printf '%s\n' "$OUT" | grep -qx 'blocked=2' || fail "blocked DNS rows were not counted"
printf '%s\n' "$OUT" | grep -qx 'unblocked=2' || fail "unblocked DNS rows were not counted"
for secret in ads.example open.example tracker.example pass.example 192.0.2.11 192.0.2.12 192.0.2.13 192.0.2.14 ClientIP; do
  ! printf '%s\n' "$OUT" | grep -Fq "$secret" || fail "summary leaked raw DNS field: $secret"
done

: > "$TMP/data/querylog.json"
[ "$(sh "$HELPER" "$TMP/data")" = FXDNSLOG_EMPTY ] || fail "empty query log was not reported"
rm -f "$TMP/data/querylog.json"
[ "$(sh "$HELPER" "$TMP/data")" = FXDNSLOG_EMPTY ] || fail "missing query log was not reported"

printf '%s\n' '{"QH":"secret.example","IsFiltered":true,"ClientIP":"192.0.2.15"}' > "$TMP/data/querylog.json"
ln -s "$TMP/data/querylog.json" "$TMP/data/querylog.link"
if sh "$HELPER" "$TMP/data/querylog.link" >/dev/null 2>&1; then fail "helper accepted an incorrect argument layout"; fi
mv "$TMP/data/querylog.json" "$TMP/data/querylog.saved"
ln -s "$TMP/data/querylog.saved" "$TMP/data/querylog.json"
if sh "$HELPER" "$TMP/data" >/dev/null 2>&1; then fail "helper followed a symlinked query log"; fi
rm -f "$TMP/data/querylog.json"
mv "$TMP/data/querylog.saved" "$TMP/data/querylog.json"
ln -s "$TMP/data" "$TMP/data-link"
if sh "$HELPER" "$TMP/data-link" >/dev/null 2>&1; then fail "helper followed a symlinked parent directory"; fi

python3 - "$CONTROL" "$PATCHER" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java" <<'PY'
from pathlib import Path
import sys
control, patcher, activity = (Path(x).read_text(encoding="utf-8") for x in sys.argv[1:])
assert '  dns-log-summary)' in control, "control command missing"
assert 'pg_get dns_querylog_enabled 0' in control, "statistics command does not honor opt-in"
assert 'yulong-ad-dns-summary.sh' in control, "control command does not invoke numeric summary helper"
assert 'yulong-ad-dns-summary.sh' in patcher and 'copy2' in patcher, "Release patcher does not stage summary helper"
assert 'root("dns-log-summary"' in activity, "native summary UI does not consume aggregate counts"
assert 'ClientIP' not in activity and 'QH' not in activity, "native summary UI must not parse or display raw log fields"
assert '最近 500 条日志样本' not in activity, "daily summary still reports the old 500-row sample instead of retained totals"
PY
echo "PASS: seven-day local DNS log summary returns numeric counts only, honors opt-in and rejects symlinked paths"
