#!/usr/bin/env python3
"""Install the native Script page settings.conf backend into the staged FX module."""
from pathlib import Path
import sys

def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch_native_script_store.py MODULE_DIR")
    module = Path(sys.argv[1]).resolve()
    source = Path(__file__).with_name("native-script-list.sh")
    if not source.is_file():
        raise SystemExit(f"native script backend source missing: {source}")
    target = module / "scripts/jsruntime/native-list.sh"
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = source.read_bytes()
    changed = not target.is_file() or target.read_bytes() != payload
    if changed:
        target.write_bytes(payload)
    target.chmod(0o755)
    print(f"native script-list backend {'installed' if changed else 'already current'}: {target}")

if __name__ == "__main__":
    main()
