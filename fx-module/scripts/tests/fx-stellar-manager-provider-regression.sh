#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
MANIFEST="$ROOT/adhook/app/src/main/AndroidManifest.xml"
SOURCE="$ROOT/adhook/app/src/main/java/roro/stellar/manager/StellarManagerProvider.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$MANIFEST" ] || fail "FX manifest missing"
[ -s "$SOURCE" ] || fail "Stellar manager compatibility provider source missing"
python3 - "$MANIFEST" "$SOURCE" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

manifest = ET.parse(sys.argv[1]).getroot()
source = Path(sys.argv[2]).read_text(encoding="utf-8")
ns = "{http://schemas.android.com/apk/res/android}"
app = manifest.find("application")
assert app is not None, "application node missing"
providers = [node for node in app.findall("provider")
             if node.get(ns + "name") == "roro.stellar.manager.StellarManagerProvider"]
assert len(providers) == 1, "original Stellar manager provider must be registered exactly once"
provider = providers[0]
assert provider.get(ns + "authorities") == "com.youlong.hd.stellar", "legacy Stellar authority changed"
assert provider.get(ns + "exported") == "true", "provider must retain its original exported contract"
assert provider.get(ns + "permission") == "android.permission.INTERACT_ACROSS_USERS_FULL",     "exported provider must retain the original signature/system permission boundary"
assert provider.get(ns + "directBootAware") == "true", "legacy provider must remain available before unlock"
assert provider.get(ns + "multiprocess") == "false", "provider state must remain process-serialized"

for method in ("saveLog", "getShizukuCompat", "saveConfig", "getLogs", "loadConfig", "clearLogs"):
    assert f'METHOD_' in source and f'"{method}"' in source, f"legacy provider call missing: {method}"
for key in ("logs", "packagesJson", "shizukuCompat", "configJson"):
    assert f'"{key}"' in source, f"legacy provider bundle key missing: {key}"

assert "createDeviceProtectedStorageContext()" in source,     "direct-boot provider must store its state in device-protected storage"
assert "MAX_LOG_ENTRIES = 500" in source and "MAX_LOG_CHARS = 4096" in source,     "provider log storage must have explicit entry and message bounds"
assert "CONFIG_LIMIT = 1024 * 1024" in source and "MAX_PACKAGE_ENTRIES = 4096" in source,     "provider config import must have bounded input and package-map sizes"
assert "Integer.parseInt(key)" in source and "packages.opt(key) instanceof JSONObject" in source,     "legacy package map must validate numeric UID keys and PackageEntry objects"
assert 'result.put("version", 1)' in source, "legacy config version must stay at v1"
assert 'result.put("shizukuCompatEnabled", true)' in source,     "original provider forces Shizuku compatibility on when saving config"
assert "preferences.edit()" in source and ".commit()" in source,     "provider API writes must be durably committed before returning success"
assert 'result.putString(KEY_CONFIG_JSON, config.toString())' in source,     "loadConfig must return the original configJson Bundle field"
assert "result.putStringArray(KEY_LOGS, logs.toArray(new String[0]))" in source,     "getLogs must retain the original String[] Bundle field"
assert 'return null;' in source[source.index("default:"):source.index("public Cursor query")],     "unsupported original AIDL daemon methods must fail closed instead of returning a fake Binder"
assert "getBinder/sendBinder/sendUserService" in source,     "unsupported AIDL daemon operations must be explicitly documented"
print("PASS: Stellar manager provider preserves protected config/log API, direct-boot state and fail-closed Binder boundary")
PY
