#!/usr/bin/env python3
"""Restore Yulong 7.0.1 app-firewall scripts after the stable Release source overlay."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module").resolve()
repo = Path(sys.argv[2] if len(sys.argv) > 2 else ".").resolve()
source_script = repo / "fx-module/scripts/yulong-app-firewall.sh"
source_test = repo / "fx-module/scripts/tests/v1.0.0-yulong-app-firewall-regression.sh"
target_script = module / "scripts/yulong-app-firewall.sh"
target_test = module / "scripts/tests/v1.0.0-yulong-app-firewall-regression.sh"

if not source_script.is_file() or source_script.stat().st_size < 5000:
    raise SystemExit("reviewed Yulong firewall implementation is missing or unexpectedly small")
if not source_test.is_file() or source_test.stat().st_size < 1000:
    raise SystemExit("Yulong firewall regression is missing or unexpectedly small")

target_script.parent.mkdir(parents=True, exist_ok=True)
target_test.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source_script, target_script)
shutil.copy2(source_test, target_test)
target_script.chmod(0o755)
target_test.chmod(0o755)

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

uninstall_anchor = "STATE_DIR=/data/adb/privacyguard\nREMOVER="
uninstall_insert = '''STATE_DIR=/data/adb/privacyguard
if [ -f "$MODDIR/scripts/yulong-app-firewall.sh" ]; then
  sh "$MODDIR/scripts/yulong-app-firewall.sh" uninstall >/dev/null 2>&1 || :
fi
REMOVER='''
if 'yulong-app-firewall.sh" uninstall' not in uninstall:
    if uninstall_anchor not in uninstall:
        raise SystemExit("uninstall.sh state anchor not found; refusing unsafe insertion")
    uninstall = uninstall.replace(uninstall_anchor, uninstall_insert, 1)

service_path.write_text(service, encoding="utf-8")
uninstall_path.write_text(uninstall, encoding="utf-8")
print("Applied Yulong 7.0.1 per-app firewall to restored FX module source.")
