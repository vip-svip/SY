#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
MANAGER="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/FxStellarManagerActivity.java"
PARSER="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/StellarCommandArguments.java"
SERVICE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/authorization/StellarAuthorizationService.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$MANAGER" ] || fail "Stellar manager Activity missing"
[ -s "$PARSER" ] || fail "Stellar command parser missing"
[ -s "$SERVICE" ] || fail "Stellar root broker service missing"

python3 - "$MANAGER" "$PARSER" "$SERVICE" <<'PY'
from pathlib import Path
import sys
manager = Path(sys.argv[1]).read_text(encoding="utf-8")
parser = Path(sys.argv[2]).read_text(encoding="utf-8")
service = Path(sys.argv[3]).read_text(encoding="utf-8")

assert 'createDeviceProtectedStorageContext()' in manager, "Stellar boot settings must use device-protected storage"
assert 'getSharedPreferences("settings",MODE_PRIVATE)' in manager, "boot mode must preserve the original Stellar settings file name"
assert 'getString("boot_mode","NONE")' in manager, "new FX installs must default to the original NONE boot mode"
assert 'putString("boot_mode",install?"SCRIPT":"NONE").commit()' in manager, "boot_mode may only change after the script operation succeeds"
assert 'root("boot-script install"' in manager and 'root("boot-script remove"' in manager and 'root("boot-script status"' in manager, \
    "install/remove/status must travel through the protected Stellar root broker"
assert 'success=1 boot_script=installed' in manager and 'success=1 boot_script=removed' in manager, \
    "UI must verify the exact backend result before reporting boot mode changes"
assert 'boot mode preference write failed' not in manager, "failure messaging must remain localized and explicit"
assert 'root("boot-script remove",rollback->' in manager, "failed SCRIPT preference commit must attempt to roll back the installed script"
assert 'BootMode=BROADCAST' in manager and 'TCPIP_PREWARM' in manager, \
    "not-yet-migrated original launch modes must be disclosed instead of exposed as fake switches"
assert 'BROADCAST 和 TCPIP_PREWARM' in manager, "UI must explain the two deferred original boot modes"
assert 'bootScriptUpdating=true;' in manager and 'bootScriptUpdating=false;' in manager, \
    "programmatic switch rollback must not trigger a second install/remove confirmation"
assert 'RootAccess.execute(' not in manager, "manager must not bypass its protected Messenger Root broker"

assert 'case "boot-script":' in parser, "boot script operations must pass the narrow command parser"
for action in ("install", "remove", "status"):
    assert f'"{action}".equals(args.get(1))' in parser, f"boot script action is missing from the exact allowlist: {action}"
assert 'boot_script' not in service, "broker does not need a separate unvalidated command bypass"
assert 'StellarCommandArguments.buildScriptCommand(args)' in service, "boot operations must still pass the command allowlist before su"
print("PASS: Stellar SCRIPT controls default to NONE, use device-protected preferences and the protected Root broker")
PY

sh "$ROOT/scripts/tests/fx-stellar-boot-script-shell-regression.sh"
