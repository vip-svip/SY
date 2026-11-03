#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaBackupActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Dia backup Activity is missing"
python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
start = source.index("private void restoreBackupBytes(")
end = source.index("private String githubContentsUrl(", start)
restore = source[start:end]
for token in (
    "stageAndValidateStellarFiles(backup)",
    "validateBackupPreferences(prefs)",
    "module.length > MAX_BACKUP_BYTES / 2",
    'expected.matches("(?i)[0-9a-f]{64}")',
):
    assert token in restore, "backup restore preflight missing: " + token
first_root_write = restore.index("RootAccess.execute(restoreCommand")
assert restore.index("validateBackupPreferences(prefs)") < first_root_write
assert restore.index("stageAndValidateStellarFiles(backup)") < first_root_write
assert restore.index("module.length > MAX_BACKUP_BYTES / 2") < first_root_write
assert restore.index("expected.equalsIgnoreCase(sha(module))") < first_root_write
assert "files.getString(name)" not in restore, "Stellar data must be decoded/validated before module mutation"
helper_start = source.index("private java.util.Map<String, java.io.File> stageAndValidateStellarFiles(")
helper_end = source.index("private void validateBackupPreferences(", helper_start)
helper = source[helper_start:helper_end]
for token in ("files.keys()", "hashes.keys()", "Base64.getDecoder().decode(encoded)",
              "expected.equalsIgnoreCase(sha(data))", "out.getFD().sync()", "totalBytes > MAX_BACKUP_BYTES"):
    assert token in helper, "Stellar preflight guard missing: " + token
print("PASS: Dia backup import validates module bytes, preferences and all allowlisted Stellar hashes before any Root write")
PY
