#!/usr/bin/env python3
"""Stage and wire the external-VPN Root Proxy watchdog into a restored FX module."""
from pathlib import Path
import shutil
import sys

module = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
repo = Path(__file__).resolve().parent.parent
source = repo / "fx-module/scripts/vpn-external-watchdog.sh"
target = module / "scripts/vpn-external-watchdog.sh"
if not source.is_file() or source.stat().st_size < 1000:
    raise SystemExit("canonical external VPN watchdog source is missing or incomplete")
target.parent.mkdir(parents=True, exist_ok=True)
if source.resolve() != target.resolve():
    shutil.copy2(source, target)
target.chmod(0o755)

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one insertion anchor, found {count}")
    return text.replace(old, new, 1)

service_path = module / "service.sh"
service = service_path.read_text(encoding="utf-8")
if 'vpn-external-watchdog.sh" snapshot' not in service:
    auto_update = '[ -f "$MODDIR/scripts/vpn-auto-update.sh" ] && sh "$MODDIR/scripts/vpn-auto-update.sh" "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1\n'
    service = replace_once(
        service, auto_update,
        auto_update + 'if [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then\n'
        '  sh "$MODDIR/scripts/vpn-external-watchdog.sh" snapshot "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "external VPN baseline unavailable; safe reconcile on start" >> "$PG/boot.log"\n'
        'fi\n',
        "service.sh snapshot",
    )
if 'vpn-external-watchdog.sh" mark-applied' not in service:
    apply_result = 'sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1\n_rc=$?\n'
    service = replace_once(
        service, apply_result,
        apply_result + 'if [ "$_rc" -eq 0 ] && [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then\n'
        '  sh "$MODDIR/scripts/vpn-external-watchdog.sh" mark-applied "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "external VPN applied-state commit failed" >> "$PG/boot.log"\n'
        'fi\n',
        "service.sh apply result",
    )
if 'vpn-external-watchdog.sh" start' not in service:
    scheduler_anchor = 'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then\n'
    service = replace_once(
        service, scheduler_anchor,
        'if [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then\n'
        '  sh "$MODDIR/scripts/vpn-external-watchdog.sh" start "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1 || echo "external VPN watcher failed to start" >> "$PG/boot.log"\n'
        'fi\n' + scheduler_anchor,
        "service.sh watcher start",
    )
service_path.write_text(service, encoding="utf-8")

uninstall_path = module / "uninstall.sh"
uninstall = uninstall_path.read_text(encoding="utf-8")
if 'vpn-external-watchdog.sh" uninstall' not in uninstall:
    root_proxy_anchor = 'if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ]; then\n'
    uninstall = replace_once(
        uninstall, root_proxy_anchor,
        'if [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then\n'
        '  if ! sh "$MODDIR/scripts/vpn-external-watchdog.sh" uninstall "$MODDIR" "$PG" >> "$PG/vpn-external-watchdog.log" 2>&1; then\n'
        '    PG_KEEP_DATA=1\n'
        '    _mitm_warn "could not confirm stopping the external VPN watcher; preserving state for safe retry"\n'
        '  fi\n'
        'fi\n' + root_proxy_anchor,
        "uninstall.sh watcher-before-Root-Proxy",
    )
uninstall_path.write_text(uninstall, encoding="utf-8")
print("Staged external VPN watchdog and wired boot snapshot/apply/start plus watcher-first uninstall cleanup.")
