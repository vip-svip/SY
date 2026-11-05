#!/usr/bin/env python3
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/patch_native_hook_config_overlay.py"
MAIN = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"

# Validate the patcher source itself before launching it in the temp fixture.
compile(PATCHER.read_text(encoding="utf-8"), str(PATCHER), "exec")
START = '''    {
      # Modern unified Hook schema. Keep xposed.conf in its legacy format for
'''
END = '''    } > "$_gxc_tmp" 2>/dev/null || { rm -f "$_gxc_tmp"; _GXC_ALL_OK=0; continue; }'''

def fail(message):
    raise SystemExit("FAIL: " + message)

with tempfile.TemporaryDirectory(prefix="fx-overlay-test-") as td:
    base = Path(td)
    root = base / "module"
    scripts = root / "scripts"
    scripts.mkdir(parents=True)
    generator = scripts / "gen_xposed_conf.sh"
    generator.write_text(
        "#!/bin/sh\n"
        "for _gxc_uid in 0; do\n"
        "  _gxc_tmp=\"$TMP/out\"\n"
        "  _GXC_ALL_OK=1\n"
        + START
        + "      printf 'legacy-generated\\\\n'\n"
        + END
        + "\ndone\n"
        + "printf '%s' \"$_GXC_ALL_OK\" > \"$TMP/status\"\n",
        encoding="utf-8",
    )
    subprocess.run([sys.executable, str(PATCHER), str(root)], check=True, capture_output=True, text=True)
    patched = generator.read_text(encoding="utf-8")
    if '_gxc_parent=$(dirname "$PG")' not in patched:
        fail("native overlay path ancestors are not validated before reads")
    if "Hook state directory ancestor is missing or symlinked" not in patched:
        fail("unsafe PG ancestor does not fail closed")
    publish = MAIN.read_text(encoding="utf-8")
    start = publish.index("private void publishConfig()")
    end = publish.index("\n    private ", start + 40)
    publish_config = publish[start:end]
    for token in ("for _d in '/data'", "for _f in", "unsafe Hook directory path",
                  "unsafe Hook publication file path"):
        if token not in publish_config:
            fail("Hook publisher path safety invariant missing: " + token)
    if "mkdir -p" in publish_config and "for _d in '/data'" not in publish_config:
        fail("Hook publisher creates directories without checking their ancestors")
    if "_GXC_NATIVE_CONFIG=\"$PG/fx-native-hook-targets-$_gxc_uid.conf\"" not in patched:
        fail("per-user native overlay path was not injected")
    if "native Hook overlay invalid" not in patched or "continue" not in patched:
        fail("invalid overlay does not fail closed")
    subprocess.run(["sh", "-n", str(generator)], check=True)

    # A valid APP-published overlay must win over the legacy generator.
    pg = base / "pg"
    pg.mkdir()
    valid = "schema_version=1\nads_enabled=1\nprivacy_enabled=0\n[list:targets]\n"
    (pg / "fx-native-hook-targets-0.conf").write_text(valid, encoding="utf-8")
    env = dict(os.environ, PG=str(pg), TMP=str(base / "valid"))
    Path(env["TMP"]).mkdir()
    subprocess.run(["sh", str(generator)], env=env, check=True)
    if (Path(env["TMP"]) / "out").read_text(encoding="utf-8") != valid:
        fail("valid native overlay was overwritten by legacy generated config")
    if (Path(env["TMP"]) / "status").read_text() != "1":
        fail("valid native overlay did not preserve generator success")

    # An invalid overlay must not silently fall back to stale legacy settings.
    (pg / "fx-native-hook-targets-0.conf").write_text("schema_version=1\n", encoding="utf-8")
    env = dict(os.environ, PG=str(pg), TMP=str(base / "invalid"))
    Path(env["TMP"]).mkdir()
    subprocess.run(["sh", str(generator)], env=env, check=True)
    if (Path(env["TMP"]) / "status").read_text() != "0":
        fail("invalid native overlay did not fail the generator")
    if (Path(env["TMP"]) / "out").exists():
        fail("invalid native overlay fell back to legacy config and overwrote APP settings")

    # A symlinked PG directory and any symlinked ancestor must never supply config.
    external_pg = base / "external-pg"
    external_pg.mkdir()
    (external_pg / "fx-native-hook-targets-0.conf").write_text(valid, encoding="utf-8")
    pg_link = base / "pg-link"
    pg_link.symlink_to(external_pg, target_is_directory=True)
    env = dict(os.environ, PG=str(pg_link), TMP=str(base / "pg-symlink"))
    Path(env["TMP"]).mkdir()
    subprocess.run(["sh", str(generator)], env=env, check=True)
    if (Path(env["TMP"]) / "status").read_text() != "0":
        fail("symlinked PG directory was accepted")
    if (Path(env["TMP"]) / "out").exists():
        fail("symlinked PG directory supplied a native config")

    real_parent = base / "real-parent"
    (real_parent / "pg").mkdir(parents=True)
    (real_parent / "pg" / "fx-native-hook-targets-0.conf").write_text(valid, encoding="utf-8")
    parent_link = base / "parent-link"
    parent_link.symlink_to(real_parent, target_is_directory=True)
    env = dict(os.environ, PG=str(parent_link / "pg"), TMP=str(base / "parent-symlink"))
    Path(env["TMP"]).mkdir()
    subprocess.run(["sh", str(generator)], env=env, check=True)
    if (Path(env["TMP"]) / "status").read_text() != "0":
        fail("symlinked PG ancestor was accepted")
    if (Path(env["TMP"]) / "out").exists():
        fail("symlinked PG ancestor supplied a native config")

    # A symlink is never trusted as the native config source.
    target = base / "target.conf"
    target.write_text(valid, encoding="utf-8")
    overlay = pg / "fx-native-hook-targets-0.conf"
    overlay.unlink()
    overlay.symlink_to(target)
    env = dict(os.environ, PG=str(pg), TMP=str(base / "symlink"))
    Path(env["TMP"]).mkdir()
    subprocess.run(["sh", str(generator)], env=env, check=True)
    if (Path(env["TMP"]) / "status").read_text() != "0":
        fail("symlinked native overlay was accepted")

    # Patcher is deterministic/idempotent on an already migrated generator.
    result = subprocess.run([sys.executable, str(PATCHER), str(root)], check=True, capture_output=True, text=True)
    if "already applied" not in result.stdout:
        fail("second patcher invocation was not idempotent")

print("PASS: native Hook overlay precedence, fail-closed validation, symlink rejection, and idempotence")
