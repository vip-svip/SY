#!/system/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
UI="$ROOT/webroot/index.html"
BE="$ROOT/scripts/fileedit.sh"
# The external-editor path must be rooted in FX's dedicated workspace and carry a source fingerprint.
grep -Fq 'Download/FX-External' "$BE"
grep -Fq 'baseHash' "$BE"
grep -Fq 'import-external)' "$BE"
grep -Fq 'source changed in FX; external import blocked to prevent overwrite conflict' "$BE"
grep -Fq 'external file exceeds 16MB limit' "$BE"
grep -Fq 'write_tmp_to "$_dst" "$_tmp"' "$BE"
# The UI launches a real Android editor activity, watches for a stable save, and imports via the backend.
grep -Fq 'function feExternalPoll(owner,path,baseHash,tries)' "$UI"
grep -Fq 'android.intent.action.EDIT' "$UI"
grep -Fq "feBtn('export',lt('用其他应用打开','Open in other app'))" "$UI"
grep -Fq "feCmd('import-external',owner.spec" "$UI"
grep -Fq 'External save detected and safely imported into FX' "$UI"
echo 'FX external editor round-trip and conflict protection regression: PASS'
