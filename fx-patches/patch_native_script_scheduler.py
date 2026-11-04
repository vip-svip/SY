#!/usr/bin/env python3
"""Stage the owned QuickJS subscription scheduler and stop it on module removal."""
from pathlib import Path
import os
import sys
import tempfile

BEGIN = "# FX_QUICKJS_SCHEDULER_STOP_BEGIN"
END = "# FX_QUICKJS_SCHEDULER_STOP_END"
ANCHOR = "STATE_DIR=/data/adb/privacyguard\n"
BLOCK = (
    BEGIN + "\n"
    + 'if [ -f "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then\n'
    + '  sh "$MODDIR/scripts/jsruntime/scheduler.sh" uninstall >> "$STATE_DIR/jsruntime/scheduler.log" 2>&1 || :\n'
    + "fi\n"
    + END + "\n"
)


def atomic_write(path: Path, payload: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise SystemExit(f"refusing to replace symlink: {path}")
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    except BaseException:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass
        raise


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_native_script_scheduler.py MODULE_DIR")
    root = Path(__file__).resolve().parents[1]
    module = Path(sys.argv[1]).resolve()
    source = root / "fx-patches/native-script-scheduler.sh"
    target = module / "scripts/jsruntime/scheduler.sh"
    uninstall = module / "uninstall.sh"
    runtime = module / "scripts/jsruntime"
    sync_subs = runtime / "sync-subs.sh"
    runner = runtime / "runner.sh"
    host = runtime / "host.js"
    if not source.is_file() or not uninstall.is_file():
        raise SystemExit("scheduler source or module uninstall.sh is missing")
    # The watcher is not a feature by itself: a restored Release must contain
    # the real HTTPS subscription synchronizer and QuickJS runner it delegates to.
    missing = [str(path.relative_to(module)) for path in (sync_subs, runner, host) if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("QuickJS subscription runtime is incomplete; missing: " + ", ".join(missing))
    payload = source.read_bytes()
    if target.is_symlink():
        raise SystemExit(f"refusing scheduler symlink: {target}")
    changed = not target.is_file() or target.read_bytes() != payload
    if changed:
        old_mode = target.stat().st_mode & 0o777 if target.exists() else 0o755
        atomic_write(target, payload, old_mode | 0o111)

    if uninstall.is_symlink():
        raise SystemExit(f"refusing uninstall symlink: {uninstall}")
    text = uninstall.read_text(encoding="utf-8")
    if BEGIN in text or END in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1 or text.index(BEGIN) > text.index(END):
            raise SystemExit("partial or duplicate QuickJS uninstall marker detected")
        if BLOCK not in text:
            raise SystemExit("QuickJS uninstall block was modified; refusing to overwrite")
        uninstall_changed = False
    else:
        if text.count(ANCHOR) != 1:
            raise SystemExit("uninstall STATE_DIR anchor is missing or ambiguous")
        text = text.replace(ANCHOR, ANCHOR + BLOCK, 1)
        mode = uninstall.stat().st_mode & 0o777
        atomic_write(uninstall, text.encode("utf-8"), mode)
        uninstall_changed = True

    print("QuickJS scheduler staged="
          + ("updated" if changed else "current")
          + "; uninstall stop hook="
          + ("added" if uninstall_changed else "current"))


if __name__ == "__main__":
    main()
