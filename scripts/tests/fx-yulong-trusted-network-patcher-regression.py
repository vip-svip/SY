#!/usr/bin/env python3
"""Regression for Yulong master-gate and trusted-Wi-Fi release restoration."""
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
patcher = repo / "fx-patches/patch_yulong_ad_master.py"

with tempfile.TemporaryDirectory(prefix="fx-yulong-trusted-patcher-") as tmp:
    module = Path(tmp) / "fx-module"
    scripts = module / "scripts"
    scripts.mkdir(parents=True)
    (scripts / "util.sh").write_text(
        'pg_list_enabled() { pg_list "$1"; }\n',
        encoding="utf-8",
    )
    (scripts / "default.conf").write_text(
        "hook_ads_enabled=0\n[list:fx]\n",
        encoding="utf-8",
    )
    (module / "service.sh").write_text(
        '#!/system/bin/sh\n'
        'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then\n'
        '  sh "$MODDIR/scripts/jsruntime/scheduler.sh" start\n'
        'fi\n',
        encoding="utf-8",
    )
    (module / "uninstall.sh").write_text(
        '#!/system/bin/sh\nPG=/data/adb/privacyguard\n'
        'REMOVER="$MODDIR/scripts/remove_adhook_app.sh"\n',
        encoding="utf-8",
    )

    def apply_patch():
        subprocess.run([sys.executable, str(patcher), str(module)],
                       cwd=repo, check=True, capture_output=True, text=True)

    apply_patch()
    service = (module / "service.sh").read_text(encoding="utf-8")
    uninstall = (module / "uninstall.sh").read_text(encoding="utf-8")
    util = (scripts / "util.sh").read_text(encoding="utf-8")
    defaults = (scripts / "default.conf").read_text(encoding="utf-8")

    assert service.count("yulong-trusted-network.sh") == 1, "trusted watcher must be inserted once"
    assert service.count("yulong-ad-schedule.sh") == 1, "weekly scheduler must be inserted once"
    assert service.index("yulong-trusted-network.sh") < service.index("yulong-ad-schedule.sh") < service.index("jsruntime/scheduler.sh"),         "Yulong watchers must start before the JS scheduler without replacing it"
    assert util.count("yulong_ad_schedule_active") == 1, "weekly schedule gate must be present exactly once"
    assert util.count("yulong_ad_trusted_active") == 1, "trusted Wi-Fi gate must be present exactly once"
    assert defaults.count("yulong_ad_schedule_active=1") == 1, "weekly schedule default must be unique"
    assert defaults.count("yulong_ad_trusted_active=1") == 1, "trusted Wi-Fi default must be unique"
    assert uninstall.count("yulong-trusted-network.sh") == 1, "uninstall must stop trusted watcher exactly once"
    assert 'yulong-trusted-network.sh" uninstall' in uninstall, "uninstall must restore owned Yulong rule gate"

    apply_patch()
    assert (module / "service.sh").read_text(encoding="utf-8") == service, "service patch must be idempotent"
    assert (module / "uninstall.sh").read_text(encoding="utf-8") == uninstall, "uninstall patch must be idempotent"
    defaults_again = (scripts / "default.conf").read_text(encoding="utf-8")
    util_again = (scripts / "util.sh").read_text(encoding="utf-8")
    assert defaults_again.count("yulong_ad_schedule_active=1") == 1, "repeat run duplicated schedule default"
    assert defaults_again.count("yulong_ad_trusted_active=1") == 1, "repeat run duplicated trusted default"
    assert util_again.count("yulong_ad_schedule_active") == 1 and util_again.count("yulong_ad_trusted_active") == 1,         "repeat run duplicated Yulong gates"

print("PASS: Yulong trusted-network source restore defines variables, gates rules, and is idempotent")
