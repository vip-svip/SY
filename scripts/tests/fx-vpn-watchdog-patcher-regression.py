#!/usr/bin/env python3
"""Regression coverage for the release-archive external VPN watchdog patcher."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_vpn_external_watchdog.py"

with tempfile.TemporaryDirectory(prefix="fx-vpn-watchdog-patcher-") as tmp:
    module = Path(tmp)
    scripts = module / "scripts"
    scripts.mkdir()
    watchdog = scripts / "vpn-external-watchdog.sh"
    watchdog.write_text("#!/system/bin/sh\n" + "# canonical release implementation\n" * 80)
    service = module / "service.sh"
    service.write_text(
        '[ -f "$MODDIR/scripts/vpn-auto-update.sh" ] && sh "$MODDIR/scripts/vpn-auto-update.sh" "$MODDIR" "$PG" >> "$PG/boot.log" 2>&1\n'
        'sh "$MODDIR/scripts/apply.sh" >> "$PG/boot.log" 2>&1\n'
        '_rc=$?\n'
        'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then\n'
        '  sh "$MODDIR/scripts/jsruntime/scheduler.sh" start\n'
        'fi\n'
    )
    uninstall = module / "uninstall.sh"
    uninstall.write_text(
        'if [ -x "$MODDIR/scripts/yulong-root-proxy.sh" ]; then\n'
        '  sh "$MODDIR/scripts/yulong-root-proxy.sh" uninstall\n'
        'fi\n'
    )

    for _ in range(2):
        subprocess.run([sys.executable, str(PATCHER), str(module)], check=True)

    patched_service = service.read_text()
    patched_uninstall = uninstall.read_text()
    assert watchdog.stat().st_size > 1000
    assert patched_service.count('vpn-external-watchdog.sh" snapshot') == 1
    assert patched_service.count('vpn-external-watchdog.sh" mark-applied') == 1
    assert patched_service.count('vpn-external-watchdog.sh" start') == 1
    assert patched_uninstall.count('vpn-external-watchdog.sh" stop') == 1
    assert patched_uninstall.index('vpn-external-watchdog.sh" stop') < patched_uninstall.index('yulong-root-proxy.sh" uninstall')
    stop_block = patched_uninstall.split('if [ -f "$MODDIR/scripts/vpn-external-watchdog.sh" ]; then', 1)[1].split("fi", 1)[0]
    assert "exit 1" in stop_block, "watcher stop failure must abort uninstall before Root Proxy teardown"
    for name in ("service.sh", "uninstall.sh"):
        subprocess.run(["sh", "-n", str(module / name)], check=True)

print("PASS: release watchdog patch is idempotent, preserves canonical code, wires boot lifecycle, and aborts unsafe uninstall.")
