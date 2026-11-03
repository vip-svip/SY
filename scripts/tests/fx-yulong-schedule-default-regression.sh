#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATCHER="$ROOT/fx-patches/patch_yulong_ad_master.py"
[ -s "$PATCHER" ] || { echo "FAIL: Yulong schedule patcher missing" >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-yulong-schedule.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/scripts"
cat > "$TMP/scripts/util.sh" <<'EOF'
pg_list_enabled() { pg_list "$1" | grep -v '^[[:space:]]*#'; }
EOF
cat > "$TMP/scripts/default.conf" <<'EOF'
hook_ads_enabled=0

[list:fx]
fxfile://anti_fraud_96110|FX anti-fraud source|1
fxfile://96110_candidate|96110 candidate|0
\n# Weekly Yulong ad schedule runtime state (1=inside schedule, default enabled).\nyulong_ad_schedule_active=1\n
EOF
cat > "$TMP/service.sh" <<'EOF'
#!/bin/sh
if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  :
fi
EOF
cat > "$TMP/uninstall.sh" <<'EOF'
#!/bin/sh
PG=/data/adb/privacyguard
XDIR=/data/local/tmp/privacyguard
EOF
python3 "$PATCHER" "$TMP"
# Re-applying the build patch must preserve the same values and hooks.
python3 "$PATCHER" "$TMP"
python3 - "$TMP/scripts/default.conf" "$TMP/uninstall.sh" "$TMP/service.sh" "$TMP/scripts/yulong-ad-schedule.sh" <<'PY'
from pathlib import Path
import sys
conf = Path(sys.argv[1]).read_text(encoding="utf-8")
uninstall = Path(sys.argv[2]).read_text(encoding="utf-8")
service = Path(sys.argv[3]).read_text(encoding="utf-8")
schedule = Path(sys.argv[4]).read_text(encoding="utf-8")
assert r"\n# Weekly Yulong ad schedule runtime state" not in conf, "escaped schedule block remains in default.conf"
assert r"\nyulong_ad_schedule_active=1\n" not in conf, "literal backslash-n schedule value remains"
assert conf.index("yulong_ad_schedule_active=1") < conf.index("[list:fx]"), "schedule state must stay in scalar key/value area before all list sections"
section = conf.split("[list:fx]", 1)[1].split("\n[", 1)[0]
entries = [line for line in section.splitlines() if line.strip() and not line.lstrip().startswith("#")]
assert entries == [
    "fxfile://anti_fraud_96110|FX anti-fraud source|1",
    "fxfile://96110_candidate|96110 candidate|0",
], "schedule state must not leak into FX anti-fraud list"
assert "yulong_ad_schedule_active=1" in conf, "schedule state default was not restored"
assert 'stop "$MODDIR" "$PG" uninstall' in uninstall, "uninstall must stop the schedule watcher without re-applying rules"
assert uninstall.index("PG=/data/adb/privacyguard") < uninstall.index("# Stop Yulong ad schedule before uninstall cleanup.") < uninstall.index("XDIR="), "schedule watcher must stop before uninstall cleanup begins"
assert "is_our_watcher()" in schedule and "/proc/$_watch_pid/cmdline" in schedule, "schedule stop must verify PID ownership before signalling"
assert 'if [ "$_uninstall_mode" = "uninstall" ]; then' in schedule, "uninstall stop mode must skip schedule state re-apply"
assert schedule.index('if [ "$_uninstall_mode" = "uninstall" ]; then') < schedule.index("pg_set yulong_ad_schedule_active 1"), "uninstall must return before re-applying Yulong rules"
assert "stop || return 1" in schedule, "disabled schedule start must surface watcher shutdown failures"
assert "if ! pg_set yulong_ad_schedule_active 1" in schedule, "normal stop must surface failure to restore the active schedule state"
assert r"\n" not in uninstall, "uninstall contains a literal backslash-n"
assert 'yulong-ad-schedule.sh" start' in service, "boot service must restore the schedule watcher"
print("PASS: Yulong schedule defaults remain outside [list:fx] and lifecycle hooks use real newlines")
PY
sh -n "$TMP/service.sh"
sh -n "$TMP/uninstall.sh"
sh -n "$TMP/scripts/yulong-ad-schedule.sh"
