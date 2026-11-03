#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATCH="$ROOT/fx-patches/patch_yulong_ad_master.py"
SCHEDULER="$ROOT/scripts/yulong-ad-schedule.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$PATCH" ] || fail "Yulong ad-master patch is missing"
[ -s "$SCHEDULER" ] || fail "Yulong schedule source is missing"
TMP=$(mktemp -d /tmp/fx-yulong-ad-master.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
MODULE="$TMP/module"
mkdir -p "$MODULE/scripts"
cat > "$MODULE/scripts/util.sh" <<'SH'
#!/system/bin/sh
pg_list_enabled() { echo legacy; }
pg_get() { echo default; }
SH
cat > "$MODULE/scripts/default.conf" <<'CONF'
hook_ads_enabled=0
yulong_ad_filter_enabled=1
[list:fx]
fxfile://anti_fraud_96110|verified anti-fraud source|1
fxfile://96110_candidate|community candidate|0
[list:rule]
builtin://Yulong_AdBlock.txt|Yulong 7.0.1|1
CONF
cat > "$MODULE/service.sh" <<'SH'
#!/system/bin/sh
if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then
  :
fi
SH
cat > "$MODULE/uninstall.sh" <<'SH'
#!/system/bin/sh
STATE_DIR=/data/adb/privacyguard
rm -rf "$MODDIR"
SH

verify_fixture() {
  python3 - "$MODULE/scripts/default.conf" "$MODULE/scripts/util.sh" \
    "$MODULE/service.sh" "$MODULE/uninstall.sh" "$MODULE/scripts/yulong-ad-schedule.sh" <<'PY'
from pathlib import Path
import sys
conf, util, service, uninstall, scheduler = map(Path, sys.argv[1:])
text = conf.read_text(encoding="utf-8")
lines = text.splitlines()
assert "\\n# Weekly Yulong ad schedule runtime state" not in text, \
    "literal escaped newline text leaked into default.conf"
keys = [i for i, line in enumerate(lines) if line.startswith("yulong_ad_schedule_active=")]
assert len(keys) == 1, f"expected exactly one schedule state key, got {len(keys)}"
first_section = next((i for i, line in enumerate(lines) if line.startswith("[")), len(lines))
assert keys[0] < first_section, "schedule state must be a top-level scalar before list sections"
assert lines[keys[0]] == "yulong_ad_schedule_active=1", "schedule default must be enabled"
fx_rows = []
in_fx = False
for line in lines:
    if line.strip() == "[list:fx]":
        in_fx = True
        continue
    if line.startswith("["):
        in_fx = False
    if in_fx and line and not line.lstrip().startswith("#"):
        fx_rows.append(line)
assert fx_rows == [
    "fxfile://anti_fraud_96110|verified anti-fraud source|1",
    "fxfile://96110_candidate|community candidate|0",
], f"FX anti-fraud section changed or gained stray rows: {fx_rows!r}"
u = util.read_text(encoding="utf-8")
assert u.count('pg_get yulong_ad_filter_enabled 1') == 1
assert u.count('pg_get yulong_ad_schedule_active 1') == 1
sv = service.read_text(encoding="utf-8")
assert sv.count('yulong-ad-schedule.sh" start') == 1, "boot must start exactly one schedule watcher"
un = uninstall.read_text(encoding="utf-8")
assert un.count('yulong-ad-schedule.sh" stop') == 1, "uninstall must stop the schedule watcher"
assert scheduler.is_file() and scheduler.stat().st_size > 0
print("PASS: schedule scalar stays outside [list:fx], and boot/uninstall own watcher lifecycle")
PY
  sh -n "$MODULE/scripts/util.sh"
  sh -n "$MODULE/scripts/yulong-ad-schedule.sh"
}

python3 "$PATCH" "$MODULE"
verify_fixture
# The patch is run by both build workflows and may be re-applied to an existing
# restored module. Verify the second run does not duplicate keys or lifecycle hooks.
python3 "$PATCH" "$MODULE"
verify_fixture
echo "PASS: Yulong ad-master patch is safe, namespace-preserving and idempotent"
