#!/usr/bin/env python3
"""Route standalone VPN lifecycle commands through apply.sh's atomic lock."""
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "fx-module")
target = root / "scripts" / "vpncore.sh"
if not target.is_file():
    raise SystemExit(f"missing VPN core source: {target}")

source = target.read_text(encoding="utf-8")
old = '''      ensure) vpn_core_ensure ;;
      stop) vpncore_stop ;;
'''
new = '''      ensure|stop)
        # All lifecycle mutations must share apply.sh's mkdir-based lock.
        # Directly invoking vpncore_start/stop here bypassed serialization and
        # allowed an external caller to race a UI apply or another lifecycle call.
        _apply="$(dirname "$0")/apply.sh"
        [ -f "$_apply" ] || { echo "vpncore: apply.sh missing; refusing unlocked lifecycle operation" >&2; exit 1; }
        exec sh "$_apply" vpn-core "$1"
        ;;
'''
if old in source:
    source = source.replace(old, new, 1)
elif new not in source:
    raise SystemExit("cannot locate standalone vpncore ensure/stop dispatch; refusing unsafe patch")
target.write_text(source, encoding="utf-8")

test = root / "scripts/tests/vpncore-standalone-lifecycle-lock-regression.sh"
test.write_text(r'''#!/system/bin/sh
# Standalone vpncore ensure/stop must delegate to apply.sh's locked command.
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$REPO/scripts/vpncore.sh"
[ -s "$SOURCE" ]
TMP=$(mktemp -d /tmp/fx-vpncore-lock.XXXXXX)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/scripts"
cp "$SOURCE" "$TMP/scripts/vpncore.sh"
: > "$TMP/scripts/util.sh"
cat > "$TMP/scripts/apply.sh" <<'STUB'
#!/system/bin/sh
printf '%s\n' "$*" > "$FX_TEST_ARGS"
STUB
chmod 0755 "$TMP/scripts/apply.sh"
export FX_TEST_ARGS="$TMP/args"
sh "$TMP/scripts/vpncore.sh" ensure
[ "$(cat "$FX_TEST_ARGS")" = "vpn-core ensure" ]
sh "$TMP/scripts/vpncore.sh" stop
[ "$(cat "$FX_TEST_ARGS")" = "vpn-core stop" ]
grep -Fq 'exec sh "$_apply" vpn-core "$1"' "$SOURCE"
echo "PASS: standalone VPN ensure/stop use the shared apply lock"
''', encoding="utf-8")
test.chmod(0o755)
subprocess.run(["sh", str(test)], check=True)
print("Patched standalone VPN lifecycle commands to use apply.sh lock; regression passed.")
