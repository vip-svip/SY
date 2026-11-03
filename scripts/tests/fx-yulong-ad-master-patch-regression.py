#!/usr/bin/env python3
"""Regression test for the Yulong ad master/schedule patch against restored releases."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "fx-patches/patch_yulong_ad_master.py"
SCHEDULE = ROOT / "scripts/yulong-ad-schedule.sh"

def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)

with tempfile.TemporaryDirectory(prefix="fx-yulong-master-patch-") as temp:
    module = Path(temp) / "module"
    scripts = module / "scripts"
    scripts.mkdir(parents=True)
    (scripts / "util.sh").write_text(
        "pg_list_enabled() { echo original; }\n", encoding="utf-8"
    )
    # Reproduce the malformed tail emitted by the old patcher. The literal
    # backslash-n sequence was appended after [list:fx], becoming a bogus rule.
    legacy_malformed_tail = (
        r"\n# Weekly Yulong ad schedule runtime state "
        r"(1=inside schedule, default enabled).\nyulong_ad_schedule_active=1\n"
    )
    default = (
        "hook_ads_enabled=0\n"
        "[list:fx]\n"
        "fxfile://anti_fraud_96110|FX anti-fraud|1\n"
        "fxfile://96110_candidate|96110 candidate|0\n"
        + legacy_malformed_tail
    )
    (scripts / "default.conf").write_text(default, encoding="utf-8")
    (module / "service.sh").write_text(
        '#!/system/bin/sh\nMODDIR=/data/adb/modules/privacyguard\nPG=/data/adb/privacyguard\n'
        'if [ -x "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then\n  :\nfi\n',
        encoding="utf-8",
    )
    (module / "uninstall.sh").write_text(
        '#!/system/bin/sh\nMODDIR=/data/adb/modules/privacyguard\n'
        "STATE_DIR=/data/adb/privacyguard\nexit 0\n",
        encoding="utf-8",
    )
    if not PATCH.is_file() or not SCHEDULE.is_file():
        fail("patcher or weekly schedule source is missing")

    def apply_patch() -> None:
        subprocess.run(
            [sys.executable, str(PATCH), str(module)],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    apply_patch()
    patched_default = (scripts / "default.conf").read_text(encoding="utf-8")
    global_section = patched_default.split("[list:", 1)[0]
    if "yulong_ad_filter_enabled=1" not in global_section:
        fail("ad master default is not in the global key/value section")
    if "yulong_ad_schedule_active=1" not in global_section:
        fail("weekly schedule state is not in the global key/value section")
    fx_section = patched_default.split("[list:fx]", 1)[1].split("\n[", 1)[0]
    rows = [line for line in fx_section.splitlines()
            if line.strip() and not line.lstrip().startswith("#")]
    if rows != [
        "fxfile://anti_fraud_96110|FX anti-fraud|1",
        "fxfile://96110_candidate|96110 candidate|0",
    ]:
        fail("schedule metadata contaminated or changed [list:fx]: " + repr(rows))
    if r"\n# Weekly Yulong ad schedule runtime state" in patched_default:
        fail("escaped newline text remains in default.conf")

    util = (scripts / "util.sh").read_text(encoding="utf-8")
    if "yulong_ad_filter_enabled" not in util or "yulong_ad_schedule_active" not in util:
        fail("both Yulong master and schedule gates must be installed")
    service = module / "service.sh"
    uninstall = module / "uninstall.sh"
    if (service.read_text(encoding="utf-8").count('yulong-ad-schedule.sh" start') != 1):
        fail("service boot must start exactly one schedule watcher")
    if (uninstall.read_text(encoding="utf-8").count('yulong-ad-schedule.sh" stop') != 1):
        fail("uninstall must stop exactly one schedule watcher")
    for shell_file in (service, uninstall, scripts / "util.sh"):
        subprocess.run(["sh", "-n", str(shell_file)], check=True)

    # Applying the patch repeatedly must not duplicate keys or lifecycle hooks.
    apply_patch()
    patched_default = (scripts / "default.conf").read_text(encoding="utf-8")
    if patched_default.count("yulong_ad_filter_enabled=1") != 1:
        fail("ad master key was duplicated on second application")
    if patched_default.count("yulong_ad_schedule_active=1") != 1:
        fail("schedule state was duplicated on second application")
    if service.read_text(encoding="utf-8").count('yulong-ad-schedule.sh" start') != 1:
        fail("schedule start hook was duplicated on second application")
    if uninstall.read_text(encoding="utf-8").count('yulong-ad-schedule.sh" stop') != 1:
        fail("schedule stop hook was duplicated on second application")

print("PASS: Yulong schedule state stays outside [list:fx], legacy escaped rows are repaired, and watcher start/stop patching is idempotent")
