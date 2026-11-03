#!/usr/bin/env python3
"""Restore Yulong 7.0.1 app-firewall scripts after the stable Release source overlay."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
repo = Path(sys.argv[2] if len(sys.argv) > 2 else ".").resolve()
source_script = repo / "scripts/yulong-app-firewall.sh"
source_test = repo / "scripts/tests/fx-yulong-app-firewall-regression.sh"
schedule_source = repo / "scripts/yulong-ad-schedule.sh"
schedule_target = module / "scripts/yulong-ad-schedule.sh"
target_script = module / "scripts/yulong-app-firewall.sh"
target_test = module / "scripts/tests/v1.0.0-yulong-app-firewall-regression.sh"

if not source_script.is_file() or source_script.stat().st_size < 5000:
    raise SystemExit("reviewed Yulong firewall implementation is missing or unexpectedly small")
if not source_test.is_file() or source_test.stat().st_size < 1000:
    raise SystemExit("Yulong firewall regression is missing or unexpectedly small")
if not schedule_source.is_file() or schedule_source.stat().st_size < 1500:
    raise SystemExit("Yulong schedule watcher source is missing or unexpectedly small")

target_script.parent.mkdir(parents=True, exist_ok=True)
target_test.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source_script, target_script)
shutil.copy2(source_test, target_test)
target_script.chmod(0o755)
target_test.chmod(0o755)
schedule_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(schedule_source, schedule_target)
schedule_target.chmod(0o755)

service_path = module / "service.sh"
uninstall_path = module / "uninstall.sh"
service = service_path.read_text(encoding="utf-8")
uninstall = uninstall_path.read_text(encoding="utf-8")

service_anchor = 'sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1\n_rc=$?'
service_insert = '''sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1
_rc=$?
if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" apply >> "$PG/boot.log" 2>&1 || \\
    echo "[$(date '+%m-%d %H:%M:%S')] Yulong per-app firewall deferred; FX main startup continues" >> "$PG/boot.log"
fi'''
if 'yulong-app-firewall.sh" apply' not in service:
    if service_anchor not in service:
        raise SystemExit("service.sh startup apply anchor not found; refusing unsafe insertion")
    service = service.replace(service_anchor, service_insert, 1)

schedule_anchor = '''if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" apply >> "$PG/boot.log" 2>&1 || \\
    echo "[$(date '+%m-%d %H:%M:%S')] Yulong per-app firewall deferred; FX main startup continues" >> "$PG/boot.log"
fi'''
schedule_insert = schedule_anchor + '''
# Start the restored 7.0.1 scheduled enable/disable watcher after FX apply.
if [ -f "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-ad-schedule.sh" start >> "$PG/boot.log" 2>&1 || \\
    echo "[$(date '+%m-%d %H:%M:%S')] Yulong ad schedule watcher failed to start" >> "$PG/boot.log"
fi'''
if 'yulong-ad-schedule.sh" start' not in service:
    if schedule_anchor not in service:
        raise SystemExit("service.sh Yulong firewall insertion anchor missing; refusing unsafe schedule insertion")
    service = service.replace(schedule_anchor, schedule_insert, 1)

# Release ZIP layouts may already contain the schedule stop hook between
# STATE_DIR and REMOVER. Insert by stable component anchors, not adjacency.
state_dir_line = "STATE_DIR=/data/adb/privacyguard\n"
remover_line = 'REMOVER="$MODDIR/scripts/remove_adhook_app.sh"'
schedule_stop_block = '''if [ -f "$MODDIR/scripts/yulong-ad-schedule.sh" ]; then
  sh "$MODDIR/scripts/yulong-ad-schedule.sh" stop >> "$STATE_DIR/yulong-ad-schedule.log" 2>&1 || :
fi
'''
firewall_stop_block = '''if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" uninstall >/dev/null 2>&1 || :
fi
'''
if 'yulong-ad-schedule.sh" stop' not in uninstall:
    if state_dir_line not in uninstall:
        raise SystemExit("uninstall.sh state directory anchor missing; refusing unsafe schedule cleanup insertion")
    uninstall = uninstall.replace(state_dir_line, state_dir_line + schedule_stop_block, 1)
if 'yulong-app-firewall.sh" uninstall' not in uninstall:
    if remover_line not in uninstall:
        raise SystemExit("uninstall.sh remover anchor missing; refusing unsafe firewall cleanup insertion")
    uninstall = uninstall.replace(remover_line, firewall_stop_block + remover_line, 1)

service_path.write_text(service, encoding="utf-8")
uninstall_path.write_text(uninstall, encoding="utf-8")
print("Applied Yulong 7.0.1 per-app firewall and scheduled enable/disable watcher to restored FX module source.")
