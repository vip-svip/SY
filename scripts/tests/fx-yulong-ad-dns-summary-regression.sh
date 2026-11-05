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

python3 - "$CONTROL" "$PATCHER" "$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java" "$ROOT/.github/dns/AdGuardHome-FX-runtime-v1.0.0.yaml" <<'PY'
from pathlib import Path
import sys
control, patcher, activity, documented_config = (Path(x).read_text(encoding="utf-8") for x in sys.argv[1:])
for token in (
    "[ -d '/data' ] && [ ! -L '/data' ]",
    "[ -d '/data/adb' ]",
    "&& [ ! -L '/data/adb' ]",
    "[ ! -L '/data/adb/modules' ]",
    "[ ! -L '/data/adb/modules_update' ]",
    r'if [ -d \"$d\" ] && [ ! -L \"$d\" ]',
    r'&& [ -f \"$d/module.prop\" ] && [ ! -L \"$d/module.prop\" ]',
    "grep -qx 'id=privacyguard'",
    "grep -qx 'version=1.0.0'",
    r'&& [ -d \"$d/scripts\" ] && [ ! -L \"$d/scripts\" ]',
    r'&& [ -f \"$d/scripts/yulong-ad-control.sh\" ]',
    r'&& [ ! -L \"$d/scripts/yulong-ad-control.sh\" ]',
):
    assert token in activity, "Root summary module resolver must reject symlinked or malformed module paths: " + token
assert '  dns-log-summary)' in control, "control command missing"
assert 'pg_get dns_querylog_enabled 0' in control, "statistics command does not honor opt-in"
assert 'yulong-ad-dns-summary.sh' in control, "control command does not invoke numeric summary helper"
assert 'yulong-ad-dns-summary.sh' in patcher and 'copy2' in patcher, "Release patcher does not stage summary helper"
assert 'root("dns-log-summary"' in activity, "native summary UI does not consume aggregate counts"
assert "new ArrayBlockingQueue<>(1)" in activity, "summary Root read queue must be bounded to one waiter"
assert "private void enqueueLatest(Runnable task)" in activity, "summary refresh must replace a stale queued request"
assert "worker.getQueue().poll();" in activity, "stale summary Root reads are not discarded"
assert "private int loadGeneration;" in activity and "final int generation = ++loadGeneration;" in activity, "summary refresh generation is missing"
assert 'root("list", generation' in activity and 'root("dns-log-summary", generation' in activity, "both summary reads must use the same refresh generation"
assert "generation != loadGeneration" in activity, "late summary results may overwrite a newer refresh"
assert "loadGeneration++;" in activity and "worker.shutdownNow();" in activity, "destroy must invalidate pending summary work"
assert 'ClientIP' not in activity and 'QH' not in activity, "native summary UI must not parse or display raw log fields"
assert '最近 500 条日志样本' not in activity, "daily summary still reports the old 500-row sample instead of retained totals"
metric_start = activity.index("private static long metric(")
render_start = activity.index("private void renderSummary(", metric_start)
metric = activity[metric_start:render_start]
assert "catch (NumberFormatException invalid)" in metric, "metric parser must handle malformed counts"
assert "return -1L;" in metric, "metric parser must reject malformed or absent counts"
assert "private static long metric" in activity and "private void renderSummary" in activity
assert 'text("Ad · 本机防护总结", 18, 0xff17212b, true)' in activity, "summary page must use the unified FX Ad identity"
assert "当前保留日志流式汇总" in activity, "summary must state that counts cover retained logs, not a daily-only window"
assert "最长保留期 30 天" in activity, "summary must disclose the actual retained-log window"
assert "游龙广告插件 · 本机防护总结" not in activity, "summary must not expose the source-app brand"
assert "最长保留期 30 天" in activity, "summary must match the documented 30-day retention"
assert 'interval: 30d' in patcher, "runtime generator must retain the documented 30-day interval"
assert 'interval: 30d' in documented_config, "documented AdGuard Home config must match runtime retention"
for fragment in ('append("\\\\n已启用规则源：', 'append("\\\\n白名单域名：', 'append("\\\\n黑名单域名：', '+ "\\\\n其中拦截：', '+ "\\\\n未拦截：'):
    assert fragment not in activity, "UI renders a literal backslash-n instead of a line break: " + fragment

PY

# Exercise the restored runtime renderer with query logging disabled and enabled.
# AdGuard Home expects YAML booleans, not the integer values 0/1.
MODULE_SOURCE="${1:-$ROOT/fx-module}"
case "$MODULE_SOURCE" in /*) ;; *) MODULE_SOURCE="$ROOT/$MODULE_SOURCE" ;; esac
if [ -z "${1:-}" ] && {
  [ ! -s "$MODULE_SOURCE/scripts/adguardhome.sh" ] ||
  [ ! -s "$MODULE_SOURCE/fxrules/anti_fraud_96110.txt" ];
}; then
  echo "SKIP: restored FX module runtime sources are not staged in the Host-only lane; the package lane passes fx-module explicitly and validates AdGuard YAML rendering."
  exit 0
fi
[ -s "$MODULE_SOURCE/scripts/adguardhome.sh" ] || fail "restored AdGuard Home lifecycle script missing"
[ -s "$MODULE_SOURCE/fxrules/anti_fraud_96110.txt" ] || fail "restored anti-fraud rules missing"
mkdir -p "$TMP/module/scripts" "$TMP/module/fxrules" "$TMP/pg"
cp "$MODULE_SOURCE/scripts/adguardhome.sh" "$TMP/module/scripts/adguardhome.sh"
cp "$MODULE_SOURCE/fxrules/anti_fraud_96110.txt" "$TMP/module/fxrules/anti_fraud_96110.txt"
python3 "$PATCHER" "$TMP/module" >/dev/null

printf 'dns_querylog_enabled=0\n' > "$TMP/pg/settings.conf"
sh "$TMP/module/scripts/adguardhome.sh" render-config "$TMP/module" "$TMP/pg" > "$TMP/querylog-off.yaml"
grep -A6 "^querylog:" "$TMP/querylog-off.yaml" | grep -qx "  enabled: false" || fail "query logging is not disabled by default"
grep -A6 "^querylog:" "$TMP/querylog-off.yaml" | grep -qx "  file_enabled: false" || fail "file logging is not disabled by default"
if grep -A6 "^querylog:" "$TMP/querylog-off.yaml" | grep -Eq "^  (enabled|file_enabled): [01]$"; then
  fail "querylog booleans were rendered as YAML integers"
fi

printf 'dns_querylog_enabled=1\n' > "$TMP/pg/settings.conf"
sh "$TMP/module/scripts/adguardhome.sh" render-config "$TMP/module" "$TMP/pg" > "$TMP/querylog-on.yaml"
grep -A6 "^querylog:" "$TMP/querylog-on.yaml" | grep -qx "  enabled: true" || fail "explicit query logging opt-in did not enable querylog"
grep -A6 "^querylog:" "$TMP/querylog-on.yaml" | grep -qx "  file_enabled: true" || fail "explicit query logging opt-in did not enable file logging"

echo "PASS: 30-day local DNS log summary returns numeric counts only, honors opt-in, emits valid YAML booleans and rejects symlinked paths"
