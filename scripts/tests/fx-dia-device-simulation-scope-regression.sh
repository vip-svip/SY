#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MAIN="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
[ -s "$MAIN" ] || { echo "FAIL: MainActivity missing" >&2; exit 1; }
python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path
s = Path(sys.argv[1]).read_text(encoding="utf-8")
start = s.index('// These identity/location transforms are intentionally limited')
end = s.index('boolean appVersionSimulation', start)
block = s[start:end]
assert 'boolean targetDebuggable = (ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;' in block
for key in ('location_simulate', 'location_provider_enabled_simulate',
            'android_id_simulate', 'time_zone_simulate'):
    assert f'targetDebuggable && enabled(p, "{key}")' in block, key
assert 'if (enabled(p, "location_simulate"))' not in block
assert 'if (enabled(p, "android_id_simulate"))' not in block
assert 'if (enabled(p, "time_zone_simulate"))' not in block
print("PASS: Dia GPS, provider, Android ID and timezone publishing is gated by target debuggable state")
PY
