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
slash = chr(92)
module_reader = source.split("private String rootModuleCommand()", 1)[1].split("private String rootStellarFilesCommand()", 1)[0]
stellar_reader = source.split("private String rootStellarFilesCommand()", 1)[1].split("private JSONObject buildBackup()", 1)[0]
for label, body in (("module settings reader", module_reader), ("Stellar state reader", stellar_reader)):
    assert slash + '"' in body, label + " must use Java-escaped shell quote delimiters"
    assert slash * 2 + '"' not in body, label + " contains over-escaped shell quotes that break Java compilation"
    assert "tr -d '" + slash * 2 + "n'" in body, label + " must pass a single literal \\n pattern to tr"
    assert "tr -d '" + slash * 4 + "n'" not in body, label + " contains an over-escaped newline pattern"
assert "[ ! -L \\"$DIR\\" ]" in stellar_reader, "Stellar backup must reject a symlinked state directory"
assert "[ ! -L \\"$DIR/$f\\" ]" in stellar_reader, "Stellar backup must reject symlinked state files"
assert "[ -d \\"$DIR\\" ] || exit 0" in stellar_reader, "backup must not create empty Stellar state when no directory exists"

assert r'line.split("\\|",3)' in source, "Stellar dump parser must split on a literal pipe delimiter"
assert r'line.split("\\\\|",3)' not in source, "Stellar dump parser must not split on backslash/empty alternatives"
assert "STATE_PENDING_EXPORT_FILE" in source, "pending export state key missing"
assert "outState.putString(STATE_PENDING_EXPORT_FILE, pendingBackupFileName)" in source, "pending export filename is not saved across recreation"
assert "state.getString(STATE_PENDING_EXPORT_FILE)" in source, "pending export filename is not restored after recreation"
assert "File.createTempFile(PENDING_EXPORT_PREFIX, \".tmp\", getCacheDir())" in source, "encrypted export is not staged in private cache"
assert "resolvePendingBackupFile(stagedName)" in source, "export result does not validate its staged cache file"
assert "deletePendingBackupFile(stagedName)" in source, "cancelled/invalid export does not clean its staged cache file"
assert "new java.io.FileInputStream(staged)" in source, "export result does not stream the staged backup"
assert "private byte[] pendingBackup;" not in source and "payload=pendingBackup" not in source, "export payload must not live only in Activity memory"
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
assert "if (!edit.commit())" in source, "backup restore must detect synchronous SharedPreferences persistence failure"
assert "staged.delete();" in restore and "moduleTemp.delete();" in restore, "restore staging files must be deleted on both success and failure"
assert "if (!edit.commit())" in source, "backup preferences must be durably committed before Root settings are restored"
helper_start = source.index("private java.util.Map<String, java.io.File> stageAndValidateStellarFiles(")
helper_end = source.index("private void validateBackupPreferences(", helper_start)
helper = source[helper_start:helper_end]
for token in ("files.keys()", "hashes.keys()", "Base64.getDecoder().decode(encoded)",
              "expected.equalsIgnoreCase(sha(data))", "validated.put(name, data)", "File.createTempFile",
              "cache.delete();", "totalBytes > MAX_BACKUP_BYTES"):
    assert token in helper, "Stellar preflight guard missing: " + token
transaction_start = source.index("private String buildTransactionalRestoreCommand(")
transaction_end = source.index("private void restoreBackupBytes(", transaction_start)
transaction = source[transaction_start:transaction_end]
for token in ("rollback(){", "FX_DIA_RESTORE_ROLLBACK_FAILED", "settings.old", ".existed", "_fx_mutating=1", "_fx_committed=1", "trap rollback EXIT"):
    assert token in transaction, "transactional Root rollback contract missing: " + token
assert transaction.count("RootAccess.execute") == 0, "Root transaction builder must only build a quoted shell command"
assert r'CONF=\"$PG/settings.conf\"' in transaction, "generated shell variables must use shell quotes, not literal backslash-quote bytes"
assert r'CONF=\\\"' not in transaction, "Java source must not over-escape generated shell quotes"
rollback_loop_start = transaction.index("rollback(){")
rollback_loop_end = transaction.index("$_fx_config_swapped", rollback_loop_start)
rollback_loop = transaction[rollback_loop_start:rollback_loop_end]
assert "if (!stellarFiles.containsKey(name)) continue;" in rollback_loop, "rollback must not delete Stellar files absent from an older/partial backup"
assert "FX_DIA_RESTORE_ROLLBACK_FAILED TXN=" in transaction, "rollback failures must preserve recovery snapshots and report their paths"
assert r'rm -rf \"$TXN\" \"$STXN\" || echo FX_DIA_RESTORE_CLEANUP_PENDING' in transaction, "snapshot cleanup must happen only after rollback succeeds"
assert r'rm -rf \"$TXN\" \"$STXN\"; ' not in transaction, "rollback must not unconditionally delete recovery snapshots"

assert transaction.count("if (!stellarFiles.containsKey(name)) continue;") == 1, "rollback must never touch Stellar files absent from this backup"
assert transaction.count("if (stellarFiles.containsKey(name))") >= 1, "commit loop must only replace staged Stellar files"
assert "|| :; echo FX_DIA_RESTORE_COMMITTED" in transaction, "post-commit cache cleanup failure must not report an already-committed restore as failed"
assert helper.index("staged.put(entry.getKey(), cache);") < helper.index("new java.io.FileOutputStream(cache, false)"), "partially written staged files must be tracked for cleanup"
print("PASS: Dia backup import validates module bytes, preferences and all allowlisted Stellar hashes before any Root write")
PY
