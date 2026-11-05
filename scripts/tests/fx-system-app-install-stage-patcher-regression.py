#!/usr/bin/env python3
"""Regression coverage for the install-time system-app deployment patch."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_system_app_install_stage.py"
BUILD_WORKFLOW = ROOT / ".github/workflows/build-fx-kernelsu.yml"
BEGIN = "# >>> fx-system-app-install-stage"
END = "# <<< fx-system-app-install-stage"

build_workflow = BUILD_WORKFLOW.read_text(encoding="utf-8")
assert "python3 fx-patches/patch_system_app_install_stage.py fx-module" in build_workflow, \
    "KernelSU ZIP build must apply the install-time system-app deployment stage"
assert "python3 scripts/tests/fx-system-app-install-stage-patcher-regression.py" in build_workflow, \
    "KernelSU ZIP build must execute the system-app stage regression"

with tempfile.TemporaryDirectory(prefix="fx-system-app-stage-") as tmp:
    module = Path(tmp)
    customize = module / "customize.sh"
    customize.write_text(
        "#!/system/bin/sh\n"
        'set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644\n'
        'ui_print "continue install"\n'
    )

    post_fs = module / "post-fs-data.sh"
    post_fs.write_text("#!/system/bin/sh\necho pre-existing boot setup\n", encoding="utf-8")

    for _ in range(2):
        subprocess.run([sys.executable, str(PATCHER), str(module)], check=True)

    patched = customize.read_text()
    assert patched.count(BEGIN) == 1
    assert patched.count(END) == 1
    for required in (
        'fx_system_app_stage() {',
        'fx_system_app_digest "$_fx_overlay_apk"',
        'overlay checksum sidecar missing; deployment refused',
        'overlay digest mismatch',
        'system/app/FX/FX.apk',
        'optional/FXUnifiedHook.apk',
        'fx_system_app_retry',
        'u:object_r:system_file:s0',
        'privapp-permissions',
        '[ ! -L "$fx_system_app_state_dir" ]',
        '[ ! -L "$fx_system_app_log" ]',
        '[ ! -L "$fx_system_app_marker" ]',
        '[ ! -L "$fx_system_app_retry" ]',
        'fx_system_app_path_is_safe "$fx_system_app_state_dir"',
        '_fx_marker_tmp=$(mktemp "$fx_system_app_marker.tmp.XXXXXX" 2>/dev/null) || _fx_marker_tmp=',
        'fx_system_app_mark_retry() {',
        'mktemp "$fx_system_app_marker.tmp.XXXXXX"',
    ):
        assert required in patched, f"missing system-app stage contract: {required}"
    subprocess.run(["sh", "-n", str(customize)], check=True)

    patched_post_fs = post_fs.read_text(encoding="utf-8")
    assert patched_post_fs.count("# >>> fx-system-app-overlay-verify") == 1
    for required in (
        'path_components_are_safe "$STATE_DIR" || retry',
        '[ -d "$APP_DIR" ] && [ ! -L "$APP_DIR" ] || retry',
        '[ -f "$APK_PATH" ] && [ ! -L "$APK_PATH" ] || retry',
        '[ -f "$SUM_PATH" ] && [ ! -L "$SUM_PATH" ] || retry',
        'mktemp "$RETRY_MARKER.tmp.XXXXXX"',
        'mktemp "$DEPLOYMENT_MARKER.tmp.XXXXXX"',
        "FX_SYSTEM_APP_STATE_DIR",
    ):
        assert required in patched_post_fs, f"missing early-boot overlay contract: {required}"
    assert (
        '[ -d "$APP_DIR" ] && [ ! -L "$APP_DIR" ] || exit 0' not in patched_post_fs
    ), "missing system-app overlay must create a retry marker, not silently skip"
    template = (ROOT / "fx-patches/fx_system_app_post_fs_data.sh").read_text(encoding="utf-8")
    assert patched_post_fs.count(template.strip()) == 1, "packaged post-fs-data block must match the canonical fail-closed template"
    subprocess.run(["sh", "-n", str(post_fs)], check=True)

    broken = module / "broken"
    broken.mkdir()
    (broken / "customize.sh").write_text("#!/system/bin/sh\necho no anchor\n")
    failed = subprocess.run(
        [sys.executable, str(PATCHER), str(broken)],
        text=True, capture_output=True
    )
    assert failed.returncode != 0, "patcher must reject a missing insertion anchor"
    assert "permission anchor changed" in failed.stderr

print("PASS: system-app install patch is idempotent, checksum-gated, retry-aware, non-privileged, and shell-valid.")
