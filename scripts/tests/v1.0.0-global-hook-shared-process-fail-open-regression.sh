#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
base = root / "adhook/app/src/main/java/de/privacyguard/adhook"
sensor = (base / "SensorPrivacyPolicy.java").read_text()
clip = (base / "ClipboardPrivacyPolicy.java").read_text()
hook = (base / "AdVisibilityHook.java").read_text()
checks = {
    "sensor rate clamp requires one package": "processPackageCount == 1" in sensor and "target.sensorRateLimit" in sensor,
    "sensor enumeration requires one package": "processPackageCount == 1" in sensor and "isEnabled(target, type)" in sensor,
    "clipboard reads require one package": "packageCount == 1" in clip and "target.clipboardReadBlock" in clip,
    "member discovery requires one package": "processPackages.size() == 1 && result instanceof Class<?>" in hook,
    "Android ID transform requires one package": "processPackages.size() != 1" in hook,
    "ad child attribution uses view context": "added.getContext().getPackageName()" in hook,
    "ad visibility checks configured package": "adTargetFor(pkg)" in hook,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS: " if ok else "FAIL: ") + name)
if failed:
    raise SystemExit(1)
PY
