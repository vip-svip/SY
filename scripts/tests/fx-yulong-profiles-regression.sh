#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
PROFILE_SOURCE="$ROOT/scripts/yulong-profiles.sh"
SCHED_SOURCE="$ROOT/scripts/yulong-profile-schedule.sh"
PATCHER="$ROOT/fx-patches/patch_yulong_profiles.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PROFILE_SOURCE" ] || fail "ProtectionProfile controller missing"
[ -s "$SCHED_SOURCE" ] || fail "ProfileSchedule watcher missing"
[ -s "$PATCHER" ] || fail "profile migration patcher missing"
sh -n "$PROFILE_SOURCE" || fail "profile controller shell syntax invalid"
sh -n "$SCHED_SOURCE" || fail "profile scheduler shell syntax invalid"
T=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-profiles.XXXXXX")
SLEEP_PID=
cleanup(){
  if [ -n "$SLEEP_PID" ]; then kill "$SLEEP_PID" 2>/dev/null || :; fi
  if [ -n "${PROFILE_MOD:-}" ] && [ -n "${PROFILE_PG:-}" ] && [ -s "$PROFILE_PG/yulong-profile-schedule.pid" ]; then
    p=$(cat "$PROFILE_PG/yulong-profile-schedule.pid" 2>/dev/null || :)
    case "$p" in ''|*[!0-9]*) p= ;; esac
    if [ -n "$p" ] && [ -r "/proc/$p/cmdline" ]; then
      cmd=$(tr '\000' ' ' < "/proc/$p/cmdline" 2>/dev/null || :)
      case "$cmd" in *"$PROFILE_MOD/scripts/yulong-profile-schedule.sh"*' watch '*) kill -TERM "$p" 2>/dev/null || : ;; esac
    fi
  fi
  rm -rf "$T"
}
trap cleanup EXIT HUP INT TERM

# Exercise the profile data model and switch transaction against isolated root state.
PROFILE_MOD="$T/module"
PROFILE_PG="$T/state"
mkdir -p "$PROFILE_MOD/scripts" "$PROFILE_PG"
printf 'id=privacyguard\n' > "$PROFILE_MOD/module.prop"
cp "$PROFILE_SOURCE" "$PROFILE_MOD/scripts/yulong-profiles.sh"
chmod 0755 "$PROFILE_MOD/scripts/yulong-profiles.sh"
cat > "$PROFILE_MOD/scripts/util.sh" <<'UTIL'
pg_get(){
  key=$1
  default=${2:-0}
  value=$(awk -F= -v key="$key" '$1==key {print substr($0,index($0,"=")+1); exit}' "$CONF" 2>/dev/null || :)
  [ -n "$value" ] || value=$default
  printf '%s\n' "$value"
}
pg_list(){
  awk -v target="[list:$1]" '
    $0==target {inside=1;next}
    /^\[/ {inside=0}
    inside {print}
  ' "$CONF"
}
pg_set(){
  key=$1; value=$2
  tmp="$CONF.tmp.$$"
  awk -v k="$key" -v v="$value" '
    BEGIN{done=0}
    !done && index($0,k"=")==1 {print k"="v;done=1;next}
    {print}
    END{if(!done)print k"="v}
  ' "$CONF" > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$CONF"
}
UTIL
cat > "$PROFILE_MOD/scripts/apply.sh" <<'APPLY'
#!/system/bin/sh
printf '%s\n' "$*" >> "$PG/profile-apply.log"
exit "${MOCK_APPLY_RC:-0}"
APPLY
chmod 0755 "$PROFILE_MOD/scripts/apply.sh"
cat > "$PROFILE_PG/settings.conf" <<'CONF'
dns_engine_adguardhome=0
yulong_ad_filter_enabled=1
[list:rule]
https://alpha.example/filter.txt|Alpha test list|1
https://beta.example/filter.txt|Beta test list|0
builtin://fx-native|FX native rules|1
[list:fx]
fxfile://anti_fraud_96110|FX anti-fraud source|1
CONF
export PG="$PROFILE_PG"
export MP="$PROFILE_MOD"
export CONF="$PROFILE_PG/settings.conf"

profile_list=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" list)
printf '%s\n' "$profile_list" | grep -Fq 'PROFILE|default|' || fail "bootstrap did not preserve a Default profile"
printf '%s\n' "$profile_list" | grep -Fq 'PROFILE|strict|' || fail "original Strict preset missing"
printf '%s\n' "$profile_list" | grep -Fq 'PROFILE|family|' || fail "original Family preset missing"
printf '%s\n' "$profile_list" | grep -Fq 'PROFILE|gaming|' || fail "original Gaming preset missing"
printf '%s\n' "$profile_list" | grep -Fq 'PROFILE|strict_family|' || fail "original Strict Family preset missing"

# Built-in profile switching installs the original remote source rows into FX's
# existing [list:rule], instead of only counting unavailable URLs.
strict_switch=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch strict)
printf '%s\n' "$strict_switch" | grep -Fq 'missing_sources=7' || fail "Strict preset did not report seven missing original sources"
[ "$(awk -F'|' '$1~/^https:\/\// && $3=="1" {n++} END{print n+0}' "$PROFILE_PG/settings.conf")" -eq 7 ] || fail "Strict preset did not add and enable seven remote sources"
grep -Fq 'builtin://fx-native|FX native rules|1' "$PROFILE_PG/settings.conf" || fail "profile switch modified FX-native rule state"
grep -Fq 'fxfile://anti_fraud_96110|FX anti-fraud source|1' "$PROFILE_PG/settings.conf" || fail "profile switch modified the separate 96110 list section"
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default >/dev/null
family_switch=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch family)
[ "$(awk -F'|' '$1~/^https:\/\// && $3=="1" {n++} END{print n+0}' "$PROFILE_PG/settings.conf")" -eq 5 ] || fail "Family preset did not activate five original URLs"
grep -Fq 'yulong_safe_search_enabled=1' "$PROFILE_PG/settings.conf" || fail "Family preset SafeSearch flag was not applied"
grep -Fq 'yulong_youtube_restricted_mode=1' "$PROFILE_PG/settings.conf" || fail "Family preset YouTube flag was not applied"
strict_family_switch=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch strict_family)
[ "$(awk -F'|' '$1~/^https:\/\// && $3=="1" {n++} END{print n+0}' "$PROFILE_PG/settings.conf")" -eq 9 ] || fail "Strict Family preset did not activate the nine-source union"
gaming_switch=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch gaming)
[ "$(awk -F'|' '$1~/^https:\/\// && $3=="1" {n++} END{print n+0}' "$PROFILE_PG/settings.conf")" -eq 2 ] || fail "Gaming preset did not activate two original URLs"
grep -Fq 'yulong_safe_search_enabled=0' "$PROFILE_PG/settings.conf" || fail "Gaming preset did not disable SafeSearch"
grep -Fq 'yulong_youtube_restricted_mode=0' "$PROFILE_PG/settings.conf" || fail "Gaming preset did not disable YouTube restriction"
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default >/dev/null

created=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-create "Study profile" 1 1)
custom_id=${created#created=}
case "$custom_id" in custom_*) : ;; *) fail "custom profile ID not returned: $created" ;; esac
# Change the currently selected sources, then verify that switching restores
# the profile's saved filter set and both original protection flags.
python3 - "$PROFILE_PG/settings.conf" <<'PY'
from pathlib import Path
import sys
import subprocess
path=Path(sys.argv[1])
s=path.read_text(encoding="utf-8")
s=s.replace("https://alpha.example/filter.txt|Alpha test list|1","https://alpha.example/filter.txt|Alpha test list|0")
s=s.replace("https://beta.example/filter.txt|Beta test list|0","https://beta.example/filter.txt|Beta test list|1")
path.write_text(s,encoding="utf-8")
PY
switched=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch "$custom_id")
printf '%s\n' "$switched" | grep -Fq "switched=$custom_id" || fail "profile switch was not applied"
grep -Fq 'https://alpha.example/filter.txt|Alpha test list|1' "$PROFILE_PG/settings.conf" || fail "profile switch did not restore alpha source"
grep -Fq 'https://beta.example/filter.txt|Beta test list|0' "$PROFILE_PG/settings.conf" || fail "profile switch did not restore beta source"
grep -Fq 'builtin://fx-native|FX native rules|1' "$PROFILE_PG/settings.conf" || fail "profile switch changed FX-native rule state"
grep -Fq 'yulong_active_profile='"$custom_id" "$PROFILE_PG/settings.conf" || fail "active profile ID not persisted"
grep -Fq 'yulong_safe_search_enabled=1' "$PROFILE_PG/settings.conf" || fail "SafeSearch flag not persisted"
grep -Fq 'yulong_youtube_restricted_mode=1' "$PROFILE_PG/settings.conf" || fail "YouTube restriction flag not persisted"

# A failed apply must restore settings.conf and profile state.
cp "$PROFILE_PG/settings.conf" "$T/settings.before"
cp "$PROFILE_PG/yulong-profiles.tsv" "$T/profiles.before"
if MOCK_APPLY_RC=9 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default > "$T/rollback.log" 2>&1; then
  fail "profile switch reported success when FX apply failed"
fi
cmp -s "$T/settings.before" "$PROFILE_PG/settings.conf" || fail "failed profile switch did not restore settings.conf"
cmp -s "$T/profiles.before" "$PROFILE_PG/yulong-profiles.tsv" || fail "failed profile switch did not restore profile table"
find "$PROFILE_PG" -maxdepth 1 -type f -name 'settings.conf.profile-backup.*' | grep -q . || fail "failed runtime rollback did not retain settings.conf backup"
find "$PROFILE_PG" -maxdepth 1 -type f -name 'yulong-profiles.tsv.profile-backup.*' | grep -q . || fail "failed runtime rollback did not retain profile-table backup"

# Weekly profile schedules are stored independently of the ad-filter schedule.
schedule=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-add "$custom_id" 22:00 07:00 0)
schedule_id=${schedule#created=}
case "$schedule_id" in schedule_*) : ;; *) fail "profile schedule ID missing" ;; esac
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-set "$schedule_id" 0 22:00 07:00 0
profile_list=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" list)
printf '%s\n' "$profile_list" | grep -Fq "SCHEDULE|$schedule_id|$custom_id|22:00|07:00|0|0" || fail "profile schedule update was not persisted"
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-remove "$schedule_id"
profile_list=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" list)
! printf '%s\n' "$profile_list" | grep -Fq "SCHEDULE|$schedule_id|" || fail "profile schedule removal failed"
if sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-delete "$custom_id" >/dev/null 2>&1; then
  fail "active custom profile was deleted without switching away"
fi
# Test original Calendar weekday indexes (Sunday=0, Monday=1) and time semantics.
mkdir -p "$T/bin"
cat > "$T/bin/date" <<'DATE'
#!/bin/sh
case "$1" in
  +%w) printf '%s\n' "${FX_PROFILE_TEST_DOW:-1}" ;;
  +%H:%M) printf '%s\n' "${FX_PROFILE_TEST_TIME:-12:00}" ;;
  +%s) printf '1700000000\n' ;;
  *) exec /bin/date "$@" ;;
esac
DATE
chmod 0755 "$T/bin/date"
[ -x "$T/bin/date" ] || fail "fake date executable bit was not set"
FX_PROFILE_TEST_DOW=0 "$T/bin/date" +%w | grep -Fqx 0 || fail "fake date command could not execute or return Sunday=0"
FX_PROFILE_TEST_TIME=12:00 "$T/bin/date" +%H:%M | grep -Fqx 12:00 || fail "fake date command could not return test time"
export PATH="$T/bin:$PATH"
date_schedule=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-add "$custom_id" 22:00 07:00 0)
date_schedule_id=${date_schedule#created=}
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-set "$date_schedule_id" 1 22:00 07:00 0 >/dev/null
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default >/dev/null
FX_PROFILE_TEST_DOW=0 FX_PROFILE_TEST_TIME=22:30 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" evaluate > "$T/sunday-evaluate.out"
grep -Fq "switched=$custom_id" "$T/sunday-evaluate.out" || {
  echo "--- Sunday evaluation output ---" >&2
  cat "$T/sunday-evaluate.out" >&2
  echo "--- profile schedule state ---" >&2
  cat "$PROFILE_PG/yulong-profile-schedules.tsv" >&2
  echo "--- active profile state ---" >&2
  grep -E '^yulong_active_profile=|^yulong_safe_search_enabled=|^yulong_youtube_restricted_mode=' "$PROFILE_PG/settings.conf" >&2 || :
  fail "Sunday=0 overnight schedule did not switch at 22:30"
}
monday_schedule=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-add default 09:00 17:00 1)
monday_id=${monday_schedule#created=}
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch "$custom_id" >/dev/null
FX_PROFILE_TEST_DOW=1 FX_PROFILE_TEST_TIME=12:00 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" evaluate > "$T/monday-evaluate.out"
grep -Fq 'switched=default' "$T/monday-evaluate.out" || {
  echo "--- Monday evaluation output ---" >&2
  cat "$T/monday-evaluate.out" >&2
  echo "--- date shim values ---" >&2
  FX_PROFILE_TEST_DOW=1 "$T/bin/date" +%w >&2
  FX_PROFILE_TEST_TIME=12:00 "$T/bin/date" +%H:%M >&2
  echo "--- profile schedule state ---" >&2
  cat "$PROFILE_PG/yulong-profile-schedules.tsv" >&2
  echo "--- active profile state ---" >&2
  grep -E '^yulong_active_profile=' "$PROFILE_PG/settings.conf" >&2 || :
  fail "Monday=1 schedule did not switch at noon"
}
# Verify zero-padded hours/minutes are parsed as decimal, never invalid octal.
early_schedule=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-add "$custom_id" 08:05 08:45 1)
early_id=${early_schedule#created=}
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default >/dev/null
FX_PROFILE_TEST_DOW=1 FX_PROFILE_TEST_TIME=08:30 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" evaluate > "$T/zero-padded-hour-minute.out"
grep -Fq "switched=$custom_id" "$T/zero-padded-hour-minute.out" || fail "08:05–08:45 schedule did not match with decimal time parsing"
midnight_schedule=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-add "$custom_id" 00:05 00:10 1)
midnight_id=${midnight_schedule#created=}
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default >/dev/null
FX_PROFILE_TEST_DOW=1 FX_PROFILE_TEST_TIME=00:07 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" evaluate > "$T/zero-padded-minute.out"
grep -Fq "switched=$custom_id" "$T/zero-padded-minute.out" || fail "00:05–00:10 schedule did not match with decimal minute parsing"
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch "$custom_id" >/dev/null
FX_PROFILE_TEST_DOW=0 FX_PROFILE_TEST_TIME=12:00 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" evaluate > "$T/sunday-outside.out"
grep -Fq 'no_matching_profile_schedule' "$T/sunday-outside.out" || fail "overnight schedule matched outside its window"
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-set "$date_schedule_id" 1 12:00 12:00 0 >/dev/null
FX_PROFILE_TEST_DOW=0 FX_PROFILE_TEST_TIME=12:00 sh "$PROFILE_MOD/scripts/yulong-profiles.sh" evaluate > "$T/equal-time.out"
grep -Fq 'no_matching_profile_schedule' "$T/equal-time.out" || fail "equal start/end incorrectly matched as all-day"
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-remove "$monday_id" >/dev/null
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-remove "$early_id" >/dev/null
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-remove "$midnight_id" >/dev/null
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" schedule-remove "$date_schedule_id" >/dev/null


sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-switch default >/dev/null
sh "$PROFILE_MOD/scripts/yulong-profiles.sh" profile-delete "$custom_id" >/dev/null
profile_list=$(sh "$PROFILE_MOD/scripts/yulong-profiles.sh" list)
! printf '%s\n' "$profile_list" | grep -Fq "PROFILE|$custom_id|" || fail "custom profile deletion failed"

# Stage the real profile scripts and patch the DNS/UI lifecycle twice to prove idempotency.
PATCH_MOD="$T/patch-module"
mkdir -p "$PATCH_MOD/scripts" "$PATCH_MOD/fxrules"
printf 'id=privacyguard\n' > "$PATCH_MOD/module.prop"
cat > "$PATCH_MOD/scripts/adguardhome.sh" <<'AGH'
#!/system/bin/sh
_pg_render_config(){
  _dns_querylog_enabled=false
  case "$_dns_querylog_enabled" in true) : ;; *) _dns_querylog_enabled=false ;; esac
  cat <<EOF_CFG
filtering:
  safe_search:
    enabled: $_pg_safe_search_active
    bing: $_pg_safe_search_flag
    duckduckgo: $_pg_safe_search_flag
    ecosia: $_pg_safe_search_flag
    google: $_pg_safe_search_flag
    pixabay: $_pg_safe_search_flag
    yandex: $_pg_safe_search_flag
    youtube: $_pg_youtube_restricted_flag
user_rules:
  - "||gjfzpt.cn^"
  - "||fzapp-test-tyy.gjfzpt.cn^"
  - "||oss.gjfzpt.cn^"
  - "||fzapp.gjfzpt.cn^"
  - "||fzapph5.gjfzpt.cn^"
EOF_CFG
}
case "${1:-}" in
  render-config) _pg_render_config ;;
  *) echo "unsupported action" >&2; exit 64 ;;
esac
AGH
cat > "$PATCH_MOD/fxrules/anti_fraud_96110.txt" <<'RULES'
DOMAIN,gjfzpt.cn,REJECT
DOMAIN,fzapp-test-tyy.gjfzpt.cn,REJECT
DOMAIN,oss.gjfzpt.cn,REJECT
DOMAIN,fzapp.gjfzpt.cn,REJECT
DOMAIN,fzapph5.gjfzpt.cn,REJECT
RULES
cat > "$PATCH_MOD/service.sh" <<'SERVICE'
#!/system/bin/sh
if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then :; fi
SERVICE
cat > "$PATCH_MOD/uninstall.sh" <<'UNINSTALL'
#!/system/bin/sh
# Stop trusted Wi-Fi pause and restore its owned gate before uninstall.
UNINSTALL
python3 "$PATCHER" "$PATCH_MOD"
python3 "$PATCHER" "$PATCH_MOD"
python3 - "$PATCH_MOD" <<'PY'
from pathlib import Path
import sys
import subprocess
m=Path(sys.argv[1])
agh=(m/"scripts/adguardhome.sh").read_text(encoding="utf-8")
service=(m/"service.sh").read_text(encoding="utf-8")
uninstall=(m/"uninstall.sh").read_text(encoding="utf-8")
assert "FX_YULONG_PROFILE_SAFE_SEARCH_V1" in agh
assert "enabled: $_pg_safe_search_active" in agh
assert "bing: $_pg_safe_search_flag" in agh and "youtube: $_pg_youtube_restricted_flag" in agh
assert "_pg_safe_search_active=true" in agh
doc=m/"docs"/"AdGuardHome-FX-runtime-config-v1.0.0.yaml"
assert doc.is_file(), "reference AdGuard Home YAML was not generated"
assert "bing: false" in doc.read_text(encoding="utf-8"), "default reference YAML must keep SafeSearch disabled"
assert "youtube: false" in doc.read_text(encoding="utf-8"), "default reference YAML must keep YouTube restriction disabled"
assert subprocess.run(["sh", str(m/"scripts"/"adguardhome.sh"), "render-config", str(m), str(m)], check=True, stdout=subprocess.PIPE).stdout == doc.read_bytes(), "reference YAML differs from runtime renderer"
assert service.count("FX_YULONG_PROFILE_SCHEDULER_START_V1")==1
assert 'yulong-profile-schedule.sh" start "$MODDIR" "$PG"' in service
assert uninstall.count("FX_YULONG_PROFILE_SCHEDULER_STOP_V1")==1
assert 'yulong-profile-schedule.sh" stop "$MODDIR" "$PG" uninstall' in uninstall
for name in ("yulong-profiles.sh","yulong-profile-schedule.sh"):
    p=m/"scripts"/name
    assert p.is_file() and p.stat().st_mode & 0o111, f"{name} was not staged executable"
print("PASS: profile patcher stages scripts and safely updates DNS, boot and uninstall paths idempotently")
PY
sh -n "$PATCH_MOD/scripts/yulong-profiles.sh"
sh -n "$PATCH_MOD/scripts/yulong-profile-schedule.sh"

# Verify the independent worker keeps a single watcher under concurrent starts.
WATCH_MOD="$T/watch-module"
WATCH_PG="$T/watch-state"
mkdir -p "$WATCH_MOD/scripts" "$WATCH_PG"
cp "$SCHED_SOURCE" "$WATCH_MOD/scripts/yulong-profile-schedule.sh"
cat > "$WATCH_MOD/scripts/yulong-profiles.sh" <<'PROFILE_STUB'
#!/system/bin/sh
[ "$1" = evaluate ] || exit 2
echo evaluate >> "$PG/evaluate.log"
PROFILE_STUB
chmod 0755 "$WATCH_MOD/scripts/"*
cat > "$WATCH_PG/yulong-profile-schedules.tsv" <<'SCHEDULES'
FXYULONGPROFILESCHEDULE1
schedule_1|default|00:00|23:59|0|0,1,2,3,4,5,6
SCHEDULES
export PG="$WATCH_PG" MP="$WATCH_MOD"
disabled_output=$(sh "$WATCH_MOD/scripts/yulong-profile-schedule.sh" start "$WATCH_MOD" "$WATCH_PG")
printf '%s\n' "$disabled_output" | grep -Fq "no-profile-schedules" || fail "disabled-only profile schedules must not start a polling watcher"
[ ! -e "$WATCH_PG/yulong-profile-schedule.pid" ] || fail "disabled-only profile schedule left a PID file"
cat > "$WATCH_PG/yulong-profile-schedules.tsv" <<'SCHEDULES'
FXYULONGPROFILESCHEDULE1
schedule_1|default|00:00|23:59|1|0,1,2,3,4,5,6
SCHEDULES"
i=0
while [ "$i" -lt 6 ]; do
  (sh "$WATCH_MOD/scripts/yulong-profile-schedule.sh" start "$WATCH_MOD" "$WATCH_PG" > "$T/start.$i.log" 2>&1) &
  i=$((i+1))
done
wait
watchers=$(ps -eo pid=,args= | awk -v script="$WATCH_MOD/scripts/yulong-profile-schedule.sh" 'index($0,script) && index($0," watch ") && $0 !~ /awk/ {n++} END{print n+0}')
[ "$watchers" -eq 1 ] || {
  echo "FAIL: concurrent profile scheduler starts created $watchers watchers" >&2
  echo "--- scheduler start logs ---" >&2
  for log in "$T"/start.*.log; do
    [ -f "$log" ] || continue
    echo "### $log" >&2
    cat "$log" >&2
  done
  echo "--- scheduler state ---" >&2
  ls -la "$WATCH_PG" >&2
  [ ! -f "$WATCH_PG/yulong-profile-schedule.log" ] || cat "$WATCH_PG/yulong-profile-schedule.log" >&2
  exit 1
}
[ -s "$WATCH_PG/yulong-profile-schedule.pid" ] || fail "profile watcher PID was not stored"
sh "$WATCH_MOD/scripts/yulong-profile-schedule.sh" stop "$WATCH_MOD" "$WATCH_PG" >/dev/null
i=0
while [ "$i" -lt 20 ]; do
  watchers=$(ps -eo pid=,args= | awk -v script="$WATCH_MOD/scripts/yulong-profile-schedule.sh" 'index($0,script) && index($0," watch ") && $0 !~ /awk/ {n++} END{print n+0}')
  [ "$watchers" -eq 0 ] && break
  sleep 0.1
  i=$((i+1))
done
[ "$watchers" -eq 0 ] || fail "profile scheduler stop left a watcher"
[ ! -e "$WATCH_PG/yulong-profile-schedule.pid" ] || fail "profile scheduler stop left PID state"
[ ! -e "$WATCH_PG/yulong-profile-schedule.runtime.lock" ] || fail "profile scheduler leaked runtime lock"
echo "PASS: Yulong ProtectionProfile CRUD, transactional switching, SafeSearch flags, independent schedules and single-watcher lifecycle"
