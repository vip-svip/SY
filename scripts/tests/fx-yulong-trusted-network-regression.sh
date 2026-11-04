#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SOURCE="$ROOT/fx-module/scripts/yulong-trusted-network.sh"
PATCHER="$ROOT/fx-patches/patch_yulong_ad_master.py"
ACTIVITY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java"
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
CONTROL="$ROOT/scripts/yulong-ad-control.sh"
SERVICE="$ROOT/fx-module/service.sh"
UNINSTALL="$ROOT/fx-module/uninstall.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] && [ -s "$PATCHER" ] && [ -s "$ACTIVITY" ] && [ -s "$MAIN" ] && [ -s "$CONTROL" ] || fail "trusted-network migration source missing"
sh -n "$SOURCE" || fail "watcher shell syntax invalid"
T=$(mktemp -d /tmp/fx-yulong-trusted.XXXXXX)
cleanup(){
  if [ -s "$T/state/yulong-trusted-network.pid" ]; then
    MP="$T/module" PG="$T/state" TEST_STATE="$T/state" PATH="$T/bin:$PATH" sh "$T/module/scripts/yulong-trusted-network.sh" uninstall >/dev/null 2>&1 || :
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM
MOD="$T/module"; STATE="$T/state"; BIN="$T/bin"
mkdir -p "$MOD/scripts" "$STATE" "$BIN"
cp "$SOURCE" "$MOD/scripts/yulong-trusted-network.sh"
cat > "$MOD/scripts/util.sh" <<'UTIL'
#!/system/bin/sh
pg_get(){ key=$1; default=$2; [ -f "$TEST_STATE/$key" ] && cat "$TEST_STATE/$key" || printf '%s\n' "$default"; }
pg_set(){ printf '%s\n' "$2" > "$TEST_STATE/$1"; }
UTIL
cat > "$MOD/scripts/apply.sh" <<'APPLY'
#!/system/bin/sh
[ "$MOCK_APPLY_FAIL" = 0 ] || exit 45
printf 'apply\n' >> "$TEST_STATE/apply.log"
exit 0
APPLY
cat > "$BIN/dumpsys" <<'DUMPSYS'
#!/bin/sh
printf 'mWifiInfo SSID: "%s", BSSID: aa:bb:cc:dd:ee:ff\n' "$MOCK_WIFI_SSID"
DUMPSYS
cat > "$BIN/cmd" <<'CMD'
#!/bin/sh
[ "$*" = 'wifi status' ] || exit 64
printf 'SSID: "%s"\n' "$MOCK_WIFI_SSID"
CMD
chmod 0755 "$MOD/scripts/"* "$BIN/"*
printf 'enabled=1\n' > "$STATE/yulong-trusted-network.conf"
printf 'Trusted-Corp\n' > "$STATE/yulong-trusted-ssids.conf"
printf '1\n' > "$STATE/yulong_ad_filter_enabled"
printf '1\n' > "$STATE/yulong_ad_schedule_active"
printf '1\n' > "$STATE/yulong_ad_trusted_active"
MOCK_WIFI_SSID='<unknown ssid>'; MOCK_APPLY_FAIL=0; export MOCK_WIFI_SSID MOCK_APPLY_FAIL
run(){ env MP="$MOD" PG="$STATE" TEST_STATE="$STATE" PATH="$BIN:$PATH" INTERVAL=5 sh "$MOD/scripts/yulong-trusted-network.sh" "$@"; }

MOCK_WIFI_SSID=Trusted-Corp; export MOCK_WIFI_SSID
out=$(run evaluate)
printf '%s\n' "$out" | grep -Fqx 'trusted=1' || fail "trusted SSID was not recognized"
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 0 ] || fail "trusted rule gate was not disabled"
[ -f "$STATE/yulong-trusted-paused" ] || fail "owned pause marker missing"
[ "$(cat "$STATE/yulong_ad_filter_enabled")" = 1 ] || fail "manual ad master was modified"
[ "$(cat "$STATE/yulong_ad_schedule_active")" = 1 ] || fail "weekly schedule was modified"

printf '0\n' > "$STATE/yulong_ad_filter_enabled"
run evaluate >/dev/null
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 1 ] || fail "manual master-off did not release trusted gate"
[ ! -e "$STATE/yulong-trusted-paused" ] || fail "ownership marker was not cleared"
[ "$(cat "$STATE/yulong_ad_filter_enabled")" = 0 ] || fail "manual master was incorrectly re-enabled"

printf '1\n' > "$STATE/yulong_ad_filter_enabled"
printf '0\n' > "$STATE/yulong_ad_schedule_active"
run evaluate >/dev/null
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 1 ] || fail "inactive weekly schedule still paused rules"
[ "$(cat "$STATE/yulong_ad_schedule_active")" = 0 ] || fail "weekly schedule was mutated"

printf '1\n' > "$STATE/yulong_ad_schedule_active"
run evaluate >/dev/null
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 0 ] || fail "trusted SSID did not pause rules"
MOCK_WIFI_SSID='<unknown ssid>'; export MOCK_WIFI_SSID
run evaluate >/dev/null
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 1 ] || fail "unknown SSID did not fail open"
[ ! -e "$STATE/yulong-trusted-paused" ] || fail "unknown SSID retained stale marker"

MOCK_WIFI_SSID=Trusted-Corp; MOCK_APPLY_FAIL=1; export MOCK_WIFI_SSID MOCK_APPLY_FAIL
if run evaluate >/dev/null 2>&1; then fail "apply failure unexpectedly succeeded"; fi
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 1 ] || fail "failed apply did not restore previous gate"
[ ! -e "$STATE/yulong-trusted-paused" ] || fail "failed apply retained pause marker"

MOCK_APPLY_FAIL=0; MOCK_WIFI_SSID=Office-Wifi; export MOCK_APPLY_FAIL MOCK_WIFI_SSID
run start >/dev/null
i=0
while [ "$i" -lt 30 ]; do [ -s "$STATE/yulong-trusted-network.pid" ] && break; sleep 0.1; i=$((i+1)); done
[ -s "$STATE/yulong-trusted-network.pid" ] || fail "watcher PID not published"
run status | grep -Fqx 'watcher=1' || fail "watcher identity not recognized"
run remove Trusted-Corp >/dev/null
run status | grep -Fqx 'watcher=0' || fail "watcher stayed alive after trusted list became empty"
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 1 ] || fail "empty trusted list did not restore the gate"

run add New-Corp-Wifi >/dev/null
grep -Fxq New-Corp-Wifi "$STATE/yulong-trusted-ssids.conf" || fail "SSID add did not persist"
if run add 'bad|ssid' >/dev/null 2>&1; then fail "SSID delimiter was accepted"; fi
if run add 123456789012345678901234567890123 >/dev/null 2>&1; then fail "SSID over 32 bytes was accepted"; fi
run remove New-Corp-Wifi >/dev/null
! grep -Fxq New-Corp-Wifi "$STATE/yulong-trusted-ssids.conf" || fail "SSID remove did not persist"
[ "$(stat -c '%a' "$STATE/yulong-trusted-ssids.conf")" = 600 ] || fail "SSID list is not private"

MOCK_WIFI_SSID=Trusted-Corp; export MOCK_WIFI_SSID
run status > "$T/status"
grep -Fq 'current_ssid=Trusted-Corp' "$T/status" || fail "status omitted current SSID"
! grep -Fq 'Trusted-Corp' "$STATE/yulong-trusted-network.log" 2>/dev/null || fail "SSID leaked into watcher log"

MOCK_WIFI_SSID=Office-Wifi; export MOCK_WIFI_SSID
run uninstall >/dev/null
[ "$(cat "$STATE/yulong_ad_trusted_active")" = 1 ] || fail "uninstall changed a gate without ownership"
[ ! -e "$STATE/yulong-trusted-paused" ] || fail "uninstall left a pause marker"

grep -Fq 'yulong_ad_trusted_active' "$PATCHER" || fail "Release patcher does not install third gate"
grep -Fq 'yulong-trusted-network.sh' "$PATCHER" || fail "Release patcher does not stage watcher"
grep -Fq 'yulong-trusted-network.sh' "$SERVICE" || fail "module boot does not start watcher"
grep -Fq 'yulong-trusted-network.sh' "$UNINSTALL" || fail "module uninstall does not stop watcher"
grep -Fq 'trusted-pause-set' "$CONTROL" || fail "Root adapter lacks pause switch"
grep -Fq 'trusted-ssid-add' "$CONTROL" || fail "Root adapter lacks SSID add"
grep -Fq 'trusted-ssid-remove' "$CONTROL" || fail "Root adapter lacks SSID remove"
grep -Fq 'renderTrustedNetworks' "$ACTIVITY" || fail "native trusted-network page missing"
grep -Fq 'case "信任的网络":' "$MAIN" || fail "trusted-network route missing"
route=$(sed -n '/case "信任的网络":/,/case "Root 代理模式":/p' "$MAIN")
printf '%s\n' "$route" | grep -Fq '"信任的网络"' || fail "trusted route is not dedicated"
printf '%s\n' "$route" | grep -Fq 'VPN 与 Root Proxy' && fail "trusted route still opens Root Proxy"
echo "PASS: trusted Wi-Fi pause ownership, master/schedule isolation, fail-open rollback, watcher lifecycle, SSID CRUD and native route"
