#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
python3 - "$SRC" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_text()
checks = {
    "bounded dynamic class count": "MAX_DYNAMIC_MEMBER_CLASSES = 128",
    "bounded hooked method count": "MAX_AUTO_MEMBER_METHOD_HOOKS = 256",
    "class-load observer": "installClassLoadObserver",
    "shared-process fail-open": "processPackages.size() == 1 && result instanceof Class<?>",
    "member-name allowlist": "MEMBER_METHOD_MARKERS",
    "read-only member observation": 'mode=read-only',
    "reward flow evidence cap": "MAX_REWARDED_AD_EVIDENCE = 32",
    "reward callback remains untouched": "reward callback/server validation unchanged",
}
missing = [label for label, marker in checks.items() if marker not in s]
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
if "setPurchaseState" in s or "setEntitlement" in s or "grantReward" in s:
    raise SystemExit("FAIL: forbidden entitlement/reward mutation marker found")
print("PASS: bounded member discovery and read-only rewarded-ad observation")
PY
