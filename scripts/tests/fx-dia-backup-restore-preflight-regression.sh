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
first_root_write = restore.index("RootAccess.execute(restoreCommand") if "RootAccess.execute(restoreCommand" in restore else restore.index("RootAccess.execute(restoreCommand,")
assert restore.index("validateBackupPreferences(prefs)") < first_root_write
assert restore.index("stageAndValidateStellarFiles(backup)") < first_root_write
assert restore.index("module.length > MAX_BACKUP_BYTES / 2") < first_root_write
assert restore.index("expected.equalsIgnoreCase(sha(module))") < first_root_write
assert "files.getString(name)" not in restore, "Stellar data must be decoded/validated before module mutation"
assert "buildTransactionalRestoreCommand(" in restore, "module settings and Stellar grants must share one Root transaction"
assert "previousPreferences" in restore and "error.addSuppressed(rollbackError)" in restore, "failed Root restore must restore app preference snapshots"
assert "staged.delete();" in restore and "moduleTemp.delete();" in restore, "restore staging files must be deleted on both success and failure"
helper_start = source.index("private java.util.Map<String, java.io.File> stageAndValidateStellarFiles(")
helper_end = source.index("private void validateBackupPreferences(", helper_start)
helper = source[helper_start:helper_end]
for token in ("files.keys()", "hashes.keys()", "Base64.getDecoder().decode(encoded)",
              "expected.equalsIgnoreCase(sha(data))", "validated.put(name, data)", "File.createTempFile",
              "staged.delete();", "totalBytes > MAX_BACKUP_BYTES"):
    assert token in helper, "Stellar preflight guard missing: " + token
transaction_start = source.index("private String buildTransactionalRestoreCommand(")
transaction_end = source.index("private void restoreBackupBytes(", transaction_start)
transaction = source[transaction_start:transaction_end]
for token in ("rollback(){", "FX_DIA_RESTORE_ROLLBACK_FAILED", "settings.old", ".existed", "_fx_mutating=1", "_fx_committed=1", "trap rollback EXIT"):
    assert token in transaction, "transactional Root rollback contract missing: " + token
assert transaction.count("RootAccess.execute") == 0, "Root transaction builder must only build a quoted shell command"
assert transaction.count("if (!stellarFiles.containsKey(name)) continue;") == 1, "rollback must never touch Stellar files absent from this backup"
assert transaction.count("if (stellarFiles.containsKey(name))") >= 1, "commit loop must only replace staged Stellar files"
assert "|| :; echo FX_DIA_RESTORE_COMMITTED" in transaction, "post-commit cache cleanup failure must not report an already-committed restore as failed"
assert helper.index("staged.put(entry.getKey(), cache);") < helper.index("new FileOutputStream(cache, false)"), "partially written staged files must be tracked for cleanup"
print("PASS: Dia backup import validates module bytes, preferences and all allowlisted Stellar hashes before any Root write")
PY
