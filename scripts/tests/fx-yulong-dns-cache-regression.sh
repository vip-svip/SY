#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONTROL="$ROOT/scripts/yulong-ad-control.sh"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongDnsActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$CONTROL" ] || fail "Yulong DNS control adapter missing"
[ -s "$ACTIVITY" ] || fail "native DNS Activity missing"
sh -n "$CONTROL" || fail "DNS control shell syntax invalid"

python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
assert 'button("重启本地 DNS 并清理缓存", this::confirmCacheFlush)' in source, \
    "DNS page has no native cache flush control"
assert 'private void confirmCacheFlush()' in source, "cache flush has no explicit confirmation flow"
assert 'root(shell("cache-flush"), 120000L' in source, "cache flush does not use an adequate Root timeout"
assert "DNS 可能短暂中断" in source, "the UI must disclose local DNS restart interruption"
assert "不会清理 Android 系统 DNS 缓存" in source, "the UI must not imply system-wide cache clearing"
assert 'output.contains("cache=flushed")' in source, "success UI is not bound to the backend result"
assert 'output.contains("dns-engine-disabled")' in source, "disabled-engine state is not reported separately"
PY

T=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-dns-cache.XXXXXX")
trap 'rm -rf "$T"' EXIT HUP INT TERM
mkdir -p "$T/module/scripts" "$T/pg"
printf 'id=privacyguard\n' > "$T/module/module.prop"
cp "$CONTROL" "$T/control.source"
python3 - "$T/control.source" "$T/control.sh" "$T/module" "$T/pg" <<'PY'
from pathlib import Path
import sys
source, output, module, state = sys.argv[1:]
text = Path(source).read_text(encoding="utf-8")
text = text.replace("/data/adb/modules/privacyguard", module, 1)
text = text.replace("PG=/data/adb/privacyguard", "PG=" + state, 1)
Path(output).write_text(text, encoding="utf-8")
PY
chmod 0755 "$T/control.sh"

cat > "$T/module/scripts/util.sh" <<'UTIL'
pg_get() {
  key=$1
  default=${2:-}
  value=$(awk -F= -v key="$key" '$1==key{v=substr($0,index($0,"=")+1)} END{print v}' "$PG/settings.conf")
  [ -n "$value" ] || value=$default
  printf '%s\n' "$value"
}
UTIL
cat > "$T/module/scripts/adguardhome.sh" <<'AGH'
#!/bin/sh
printf 'adguardhome:%s\n' "$1" >> "$MOCK_LOG"
case "$1" in
  stop) exit "${MOCK_AGH_STOP_RC:-0}" ;;
  ensure) exit "${MOCK_AGH_ENSURE_RC:-0}" ;;
  *) exit 2 ;;
esac
AGH
cat > "$T/module/scripts/unbound.sh" <<'UNBOUND'
#!/bin/sh
printf 'unbound:%s\n' "$1" >> "$MOCK_LOG"
case "$1" in
  stop) exit "${MOCK_UNBOUND_STOP_RC:-0}" ;;
  ensure) exit "${MOCK_UNBOUND_ENSURE_RC:-0}" ;;
  *) exit 2 ;;
esac
UNBOUND
cat > "$T/module/scripts/apply.sh" <<'APPLY'
#!/bin/sh
printf 'apply:%s\n' "$1" >> "$MOCK_LOG"
exit "${MOCK_APPLY_RC:-0}"
APPLY
chmod 0755 "$T/module/scripts/"*
export MOCK_LOG="$T/mock.log"
run(){ sh "$T/control.sh" "$@"; }

printf 'dns_engine_adguardhome=1\ndns_forward=1\n' > "$T/pg/settings.conf"
run cache-flush > "$T/success.out"
grep -Fq 'cache=flushed' "$T/success.out" || fail "successful resolver restart was not reported as flushed"
cat > "$T/expected.log" <<'EXPECTED'
adguardhome:stop
unbound:stop
unbound:ensure
adguardhome:ensure
apply:fast
EXPECTED
cmp -s "$T/expected.log" "$MOCK_LOG" || fail "resolver stop/ensure/apply order was incorrect"
[ ! -d "$T/pg/yulong-cache-flush.lock" ] || fail "success left the cache operation lock behind"

# A failed stop is not a successful flush even if subsequent ensure succeeds.
: > "$MOCK_LOG"
if MOCK_UNBOUND_STOP_RC=7 run cache-flush > "$T/stop-failed.out" 2>&1; then
  fail "failed Unbound stop was reported as a successful cache flush"
fi
grep -Fq 'unbound_stop_exit=7' "$T/stop-failed.out" || fail "Unbound stop failure code was not surfaced"
! grep -Fq 'cache=flushed' "$T/stop-failed.out" || fail "stop failure still emitted a success marker"
[ ! -d "$T/pg/yulong-cache-flush.lock" ] || fail "stop failure left the cache operation lock behind"

# A failed resolver ensure or FX routing re-apply must also fail the operation.
if MOCK_AGH_ENSURE_RC=8 run cache-flush > "$T/agh-failed.out" 2>&1; then
  fail "failed AdGuard Home ensure was reported as a successful flush"
fi
grep -Fq 'adguardhome_exit=8' "$T/agh-failed.out" || fail "AdGuard Home ensure failure was not surfaced"
if MOCK_APPLY_RC=9 run cache-flush > "$T/apply-failed.out" 2>&1; then
  fail "failed FX DNS re-apply was reported as a successful flush"
fi
grep -Fq 'apply_exit=9' "$T/apply-failed.out" || fail "FX DNS re-apply failure was not surfaced"

# Forward-only mode restarts Unbound without starting an unused AdGuard Home.
: > "$MOCK_LOG"
printf 'dns_engine_adguardhome=0\ndns_forward=1\n' > "$T/pg/settings.conf"
run cache-flush > "$T/forward-only.out"
grep -Fq 'cache=flushed' "$T/forward-only.out" || fail "forward-only DNS cache flush failed"
grep -Fq 'unbound:stop' "$MOCK_LOG" || fail "forward-only mode did not restart Unbound"
! grep -Fq 'adguardhome:' "$MOCK_LOG" || fail "forward-only mode touched disabled AdGuard Home"


# Independent engine combinations restart only the resolver engines enabled in config.
: > "$MOCK_LOG"
printf 'dns_engine_adguardhome=1\ndns_forward=0\n' > "$T/pg/settings.conf"
run cache-flush > "$T/agh-only.out"
grep -Fq 'cache=flushed' "$T/agh-only.out" || fail "AdGuard Home-only cache flush failed"
cat > "$T/agh-only.expected" <<'EXPECTED'
adguardhome:stop
adguardhome:ensure
apply:fast
EXPECTED
cmp -s "$T/agh-only.expected" "$MOCK_LOG" || fail "AdGuard Home-only mode restarted an unrelated Unbound service"

# Missing enabled helpers are errors, not successful no-op cache flushes.
: > "$MOCK_LOG"
printf 'dns_engine_adguardhome=0\ndns_forward=1\n' > "$T/pg/settings.conf"
mv "$T/module/scripts/unbound.sh" "$T/module/scripts/unbound.sh.disabled"
if run cache-flush > "$T/unbound-missing.out" 2>&1; then
  fail "missing enabled Unbound helper was reported as successful"
fi
grep -Fq 'Unbound is enabled but its FX lifecycle helper is missing' "$T/unbound-missing.out" || fail "missing Unbound helper reason was not surfaced"
[ ! -s "$MOCK_LOG" ] || fail "missing Unbound helper still executed resolver or apply actions"
mv "$T/module/scripts/unbound.sh.disabled" "$T/module/scripts/unbound.sh"

printf 'dns_engine_adguardhome=1\ndns_forward=0\n' > "$T/pg/settings.conf"
mv "$T/module/scripts/adguardhome.sh" "$T/module/scripts/adguardhome.sh.disabled"
if run cache-flush > "$T/agh-missing.out" 2>&1; then
  fail "missing enabled AdGuard Home helper was reported as successful"
fi
grep -Fq 'AdGuard Home is enabled but its FX lifecycle helper is missing' "$T/agh-missing.out" || fail "missing AdGuard Home helper reason was not surfaced"
mv "$T/module/scripts/adguardhome.sh.disabled" "$T/module/scripts/adguardhome.sh"

# No active resolver means no-op; a contended lock must not be removed by this process.
: > "$MOCK_LOG"
printf 'dns_engine_adguardhome=0\ndns_forward=0\n' > "$T/pg/settings.conf"
[ "$(run cache-flush)" = "dns-engine-disabled" ] || fail "disabled DNS engine was not reported as a no-op"
mkdir "$T/pg/yulong-cache-flush.lock"
if run cache-flush > "$T/busy.out" 2>&1; then fail "concurrent cache flush was not rejected"; fi
[ -d "$T/pg/yulong-cache-flush.lock" ] || fail "busy operation removed another process's lock"
grep -Fq 'already running' "$T/busy.out" || fail "cache lock contention was not surfaced"

echo "PASS: native DNS cache flush confirmation, resolver restart order, failure propagation, forward-only mode and lock ownership"
