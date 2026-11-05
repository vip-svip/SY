#!/usr/bin/env python3
"""Behavioural regression for the install-time system-app deployment stage.

The patcher regression proves the *patch* is idempotent and shell-valid. This
suite proves the *injected stage actually behaves correctly* when the installer
runs it, using the production shell code extracted from a patched
``customize.sh`` (no re-implementation of the logic).

Covered contract:
  1. a valid checksum-matched overlay deploys and commits a digest marker;
  2. a digest mismatch fails closed and never records success;
  3. an overlay without a checksum sidecar fails closed;
  4. a malformed checksum sidecar fails closed;
  5. a legacy archive stages the overlay from ``optional/FXUnifiedHook.apk``;
  6. an archive with no payload at all skips cleanly;
  7. redeployment is idempotent.

The suite is self-contained: it builds a synthetic ``customize.sh`` containing
the real insertion anchor, so it does not need the published Release archive.
"""
from __future__ import annotations

import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_system_app_install_stage.py"
BEGIN = "# >>> fx-system-app-install-stage"
STOP = "if fx_system_app_stage; then"

SYNTHETIC_CUSTOMIZE = """#!/system/bin/sh
ui_print "Installing FX"
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
ui_print "continue install"
"""

HARNESS = """set -u
ui_print() { printf '%s\\n' "$*"; }
. "$STAGE_LIB"
fx_system_app_stage
"""


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_patched_module(tmp: Path) -> Path:
    # The production patcher re-syncs the packaged installer/remover from the
    # canonical repository scripts. Give this isolated fixture the same layout.
    canonical_dir = tmp / "scripts"
    canonical_dir.mkdir(parents=True)
    for name in ("install_adhook_app.sh", "remove_adhook_app.sh"):
        canonical = ROOT / "scripts" / name
        assert canonical.is_file(), f"canonical {name} fixture is missing"
        (canonical_dir / name).write_text(canonical.read_text(encoding="utf-8"), encoding="utf-8")

    module = tmp / "fx-module"
    module.mkdir(parents=True)
    # The production patcher syncs into an existing packaged scripts directory.
    # Keep the fixture's target layout separate from the canonical source tree.
    (module / "scripts").mkdir()
    customize = module / "customize.sh"
    customize.write_text(SYNTHETIC_CUSTOMIZE, encoding="utf-8")

    # Apply twice: the installer may patch an already-patched tree.
    for _ in range(2):
        subprocess.run([sys.executable, str(PATCHER), str(module)], check=True)

    for name in ("install_adhook_app.sh", "remove_adhook_app.sh"):
        assert (module / "scripts" / name).read_bytes() == (canonical_dir / name).read_bytes(), (
            f"patcher must synchronize canonical {name} into the module fixture"
        )

    patched = customize.read_text(encoding="utf-8")
    assert patched.count(BEGIN) == 1, "install stage must appear exactly once after a double patch"
    subprocess.run(["sh", "-n", str(customize)], check=True)
    return module


def extract_stage(customize: Path, tmp: Path) -> Path:
    lines = customize.read_text(encoding="utf-8").splitlines()
    started = False
    body: list[str] = []
    for line in lines:
        if not started:
            if BEGIN in line:
                started = True
            continue
        if line.startswith(STOP):
            break
        body.append(line)
    assert body, "extracted install stage is empty"
    stage = tmp / "stage.sh"
    stage.write_text("\n".join(body) + "\n", encoding="utf-8")
    subprocess.run(["sh", "-n", str(stage)], check=True)
    return stage


def run_stage(stage: Path, tmp: Path, module: Path, state: Path) -> subprocess.CompletedProcess:
    harness = tmp / "harness.sh"
    harness.write_text(HARNESS, encoding="utf-8")
    env = {
        "MODPATH": str(module),
        "STAGE_LIB": str(stage),
        "FX_SYSTEM_APP_STATE_DIR": str(state),
        "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    }
    return subprocess.run(["sh", str(harness)], env=env, text=True, capture_output=True)


def make_payload(module: Path, label: str) -> Path:
    overlay = module / "system/app/FX"
    overlay.mkdir(parents=True, exist_ok=True)
    (module / "optional").mkdir(parents=True, exist_ok=True)
    apk = overlay / "FX.apk"
    apk.write_bytes(f"FX-APK-PAYLOAD-{label}\n".encode())
    (overlay / "FX.apk.sha256").write_text(f"{sha256_of(apk)}  FX.apk\n", encoding="utf-8")
    return apk


def case(name: str) -> None:
    print(f"== {name} ==")


def main() -> None:
    assert PATCHER.is_file(), f"missing patcher: {PATCHER}"

    with tempfile.TemporaryDirectory(prefix="fx-sysapp-behaviour-") as raw:
        tmp = Path(raw)
        module = build_patched_module(tmp)
        stage = extract_stage(module / "customize.sh", tmp)

        case("case 1: valid overlay deploys and commits a digest marker")
        base = tmp / "c1"
        module1 = base / "module"
        state1 = base / "state"
        apk1 = make_payload(module1, "valid")
        done = run_stage(stage, tmp, module1, state1)
        assert done.returncode == 0, f"valid overlay must deploy (rc={done.returncode}): {done.stdout}{done.stderr}"
        marker = state1 / "system-app-apk.sha256"
        assert marker.is_file(), "deployment marker was not written"
        assert marker.read_text().strip() == sha256_of(apk1), "deployment marker digest mismatch"
        assert not (state1 / "system-app-retry").exists(), "success must clear the retry marker"
        print("  ok: valid overlay deployed")

        case("case 2: digest mismatch fails closed")
        module2 = tmp / "c2/module"
        state2 = tmp / "c2/state"
        make_payload(module2, "corrupt")
        (module2 / "system/app/FX/FX.apk.sha256").write_text("0" * 64 + "  FX.apk\n", encoding="utf-8")
        bad = run_stage(stage, tmp, module2, state2)
        assert bad.returncode != 0, "digest mismatch must fail"
        assert not (state2 / "system-app-apk.sha256").exists(), "failed deploy must not record success"
        assert "摘要与校验清单不一致" in bad.stdout, f"mismatch not surfaced to the installer: {bad.stdout}"
        print("  ok: corrupt overlay refused")

        case("case 3: overlay without checksum sidecar fails closed")
        module3 = tmp / "c3/module"
        state3 = tmp / "c3/state"
        make_payload(module3, "nosum")
        (module3 / "system/app/FX/FX.apk.sha256").unlink()
        nosum = run_stage(stage, tmp, module3, state3)
        assert nosum.returncode != 0, "missing checksum must fail"
        assert not (state3 / "system-app-apk.sha256").exists(), "no marker without a checksum"
        print("  ok: missing checksum refused")

        case("case 4: malformed checksum sidecar fails closed")
        module4 = tmp / "c4/module"
        state4 = tmp / "c4/state"
        make_payload(module4, "bad")
        (module4 / "system/app/FX/FX.apk.sha256").write_text("not-a-sha256  FX.apk\n", encoding="utf-8")
        malformed = run_stage(stage, tmp, module4, state4)
        assert malformed.returncode != 0, "malformed checksum must fail"
        print("  ok: malformed checksum refused")

        case("case 5: legacy archive stages the overlay from the optional payload")
        module5 = tmp / "c5/module"
        state5 = tmp / "c5/state"
        (module5 / "optional").mkdir(parents=True)
        legacy = module5 / "optional/FXUnifiedHook.apk"
        legacy.write_bytes(b"FX-LEGACY-PAYLOAD\n")
        staged = run_stage(stage, tmp, module5, state5)
        assert staged.returncode == 0, f"legacy payload must stage (rc={staged.returncode}): {staged.stdout}{staged.stderr}"
        overlay_apk = module5 / "system/app/FX/FX.apk"
        overlay_sum = module5 / "system/app/FX/FX.apk.sha256"
        assert overlay_apk.is_file(), "legacy payload did not materialise the overlay"
        assert overlay_sum.is_file(), "legacy staging did not write a checksum sidecar"
        expected = sha256_of(legacy)
        assert overlay_sum.read_text().split()[0] == expected, "staged checksum does not match the optional payload"
        assert sha256_of(overlay_apk) == expected, "staged content differs from the optional payload"
        assert (state5 / "system-app-apk.sha256").read_text().strip() == expected, "legacy staging did not commit a marker"
        print("  ok: legacy payload promoted to a validated overlay")

        case("case 6: archive without any payload skips cleanly")
        module6 = tmp / "c6/module"
        state6 = tmp / "c6/state"
        module6.mkdir(parents=True)
        skipped = run_stage(stage, tmp, module6, state6)
        assert skipped.returncode == 0, f"absent payload must be a clean skip: {skipped.stdout}{skipped.stderr}"
        assert not (module6 / "system").exists(), "skip path must not create a system-app tree"
        assert not (state6 / "system-app-apk.sha256").exists(), "skip path must not write a marker"
        assert "未包含系统应用载荷" in skipped.stdout, "skip was not reported to the installer"
        print("  ok: absent payload skipped")

        case("case 7: redeploy is idempotent")
        first = (state1 / "system-app-apk.sha256").read_text()
        again = run_stage(stage, tmp, module1, state1)
        assert again.returncode == 0, f"repeat deployment must succeed: {again.stdout}{again.stderr}"
        assert (state1 / "system-app-apk.sha256").read_text() == first, "repeat deployment changed the marker"
        print("  ok: repeat deployment stable")

    print("PASS: install-stage system-app deployment validates, stages, fails closed and stays idempotent")


if __name__ == "__main__":
    main()
