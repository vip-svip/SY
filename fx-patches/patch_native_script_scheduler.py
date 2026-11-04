#!/usr/bin/env python3
"""Stage the owned QuickJS scheduler and replace legacy uninstall shutdown safely."""
from pathlib import Path
import os
import sys
import tempfile

BEGIN = "# FX_QUICKJS_SCHEDULER_STOP_BEGIN"
END = "# FX_QUICKJS_SCHEDULER_STOP_END"
LEGACY_BEGIN = "# Stop the background script-subscription scheduler before user data is removed."
LEGACY_END = 'rm -f "$PG/jsruntime/scheduler.pid" 2>/dev/null || :'

BLOCK = (
    BEGIN + "\n"
    + '_FX_SCHEDULER_STATE_DIR=${PG:-${STATE_DIR:-/data/adb/privacyguard}}\n'
    + 'if [ -f "$MODDIR/scripts/jsruntime/scheduler.sh" ]; then\n'
    + '  if ! sh "$MODDIR/scripts/jsruntime/scheduler.sh" uninstall >> "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.log" 2>&1; then\n'
    + '    echo "FX uninstall: QuickJS scheduler did not confirm shutdown; preserving state and aborting cleanup" >&2\n'
    + '    exit 1\n'
    + '  fi\n'
    + 'elif [ -s "$_FX_SCHEDULER_STATE_DIR/jsruntime/scheduler.pid" ]; then\n'
    + '  echo "FX uninstall: scheduler PID record exists but scheduler script is missing; aborting cleanup" >&2\n'
    + '  exit 1\n'
    + 'fi\n'
    + 'unset _FX_SCHEDULER_STATE_DIR\n'
    + END + "\n"
)
OLD_BLOCK = (
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

def replace_uninstall_block(uninstall: Path) -> bool:
    if uninstall.is_symlink():
        raise SystemExit(f"refusing uninstall symlink: {uninstall}")
    text = uninstall.read_text(encoding="utf-8")
    begin_count, end_count = text.count(BEGIN), text.count(END)
    if begin_count or end_count:
        if begin_count != 1 or end_count != 1:
            raise SystemExit("partial or duplicate QuickJS uninstall markers detected")
        start = text.index(BEGIN)
        end = text.index(END, start) + len(END)
        line_end = text.find("\\n", end)
        if line_end < 0:
            line_end = len(text)
        else:
            line_end += 1
        existing = text[start:line_end]
        if existing == BLOCK:
            return False
        if existing != OLD_BLOCK:
            raise SystemExit("QuickJS uninstall block was modified; refusing to overwrite")
        updated = text[:start] + BLOCK + text[line_end:]
    else:
        if text.count(LEGACY_BEGIN) != 1 or text.count(LEGACY_END) != 1:
            raise SystemExit("legacy QuickJS scheduler uninstall block is missing or ambiguous")
        start = text.index(LEGACY_BEGIN)
        end_marker = text.index(LEGACY_END, start)
        line_end = text.find("\\n", end_marker)
        if line_end < 0:
            line_end = len(text)
        else:
            line_end += 1
        updated = text[:start] + BLOCK + text[line_end:]
    mode = uninstall.stat().st_mode & 0o777
    atomic_write(uninstall, updated.encode("utf-8"), mode)
    return True

def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_native_script_scheduler.py MODULE_DIR")
    root = Path(__file__).resolve().parents[1]
    module = Path(sys.argv[1]).resolve()
    source = root / "fx-patches/native-script-scheduler.sh"
    target = module / "scripts/jsruntime/scheduler.sh"
    uninstall = module / "uninstall.sh"
    runtime = module / "scripts/jsruntime"
    dependencies = (runtime / "sync-subs.sh", runtime / "runner.sh", runtime / "host.js")
    if not source.is_file() or not uninstall.is_file():
        raise SystemExit("scheduler source or module uninstall.sh is missing")
    missing = [str(path.relative_to(module)) for path in dependencies if not path.is_file() or path.stat().st_size == 0]
    if missing:
        raise SystemExit("QuickJS subscription runtime is incomplete; missing: " + ", ".join(missing))
    if target.is_symlink():
        raise SystemExit(f"refusing scheduler symlink: {target}")
    payload = source.read_bytes()
    changed = not target.is_file() or target.read_bytes() != payload
    if changed:
        old_mode = target.stat().st_mode & 0o777 if target.exists() else 0o755
        atomic_write(target, payload, old_mode | 0o111)
    uninstall_changed = replace_uninstall_block(uninstall)
    print("QuickJS scheduler staged=" + ("updated" if changed else "current")
          + "; uninstall stop hook=" + ("updated" if uninstall_changed else "current"))

if __name__ == "__main__":
    main()
