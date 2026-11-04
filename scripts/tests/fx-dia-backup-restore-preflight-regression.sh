#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaBackupActivity.java"
POLICY="$ROOT/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGithubBackupPolicy.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$SOURCE" ] || fail "Dia backup Activity is missing"
python3 - "$SOURCE" "$POLICY" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text(encoding="utf-8")
policy = Path(sys.argv[2]).read_text(encoding="utf-8")
slash = chr(92)
module_reader = source.split("private String rootModuleCommand()", 1)[1].split("private String rootStellarFilesCommand()", 1)[0]
stellar_reader = source.split("private String rootStellarFilesCommand()", 1)[1].split("private JSONObject buildBackup()", 1)[0]
for label, body in (("module settings reader", module_reader), ("Stellar state reader", stellar_reader)):
    if label == "module settings reader":
        assert '[ ! -L ' + slash + '"$PG' + slash + '" ]' in body, "module backup must reject a symlinked state directory"
        assert '[ ! -L ' + slash + '"$PG/settings.conf' + slash + '" ]' in body, "module backup must reject a symlinked settings file"
    assert slash + '"' in body, label + " must use Java-escaped shell quote delimiters"
    assert slash * 2 + '"' not in body, label + " contains over-escaped shell quotes that break Java compilation"
    assert "tr -d '" + slash * 2 + "n'" in body, label + " must pass a single literal \\n pattern to tr"
    assert "tr -d '" + slash * 4 + "n'" not in body, label + " contains an over-escaped newline pattern"
assert r'[ ! -L \"$DIR\" ]' in stellar_reader, "Stellar backup must reject a symlinked state directory"
assert r'[ ! -L \"$DIR/$f\" ]' in stellar_reader, "Stellar backup must reject symlinked state files"
assert r'[ -d \"$DIR\" ] || exit 0' in stellar_reader, "backup must not create empty Stellar state when no directory exists"

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
for token in ("rollback(){", "cleanup_txn(){", "FX_DIA_RESTORE_ROLLBACK_FAILED",
              "FX_DIA_RESTORE_CLEANUP_PENDING", "settings.old", ".existed",
              "_fx_mutating=1", "_fx_committed=1", "trap rollback EXIT",
              "_fx_txn_created=0", "_fx_stxn_created=0"):
    assert token in transaction, "transactional Root rollback/cleanup contract missing: " + token
assert transaction.count("RootAccess.execute") == 0, "Root transaction builder must only build a quoted shell command"
assert r'CONF=\"$PG/settings.conf\"' in transaction, "generated shell variables must use shell quotes"
assert r'CONF=\\\"' not in transaction, "Java source must not over-escape generated shell quotes"
assert 'append("mkdir -p \\"$DIR\\"' not in transaction, "transaction must never recursively create/follow a symlinked parent"
assert 'append("rm -rf \\"$TXN\\" \\"$STXN\\"' not in transaction, "unconditional paired cleanup must be removed"
assert transaction.count('if [ \\"$_fx_txn_created\\" -eq 1 ]; then') == 1
assert transaction.count('if [ \\"$_fx_stxn_created\\" -eq 1 ]; then') == 1
assert transaction.index('mkdir \\"$TXN\\" || exit 45; _fx_txn_created=1;') < transaction.index('mkdir \\"$STXN\\" || exit 46; _fx_stxn_created=1;')
cleanup_start = transaction.index("cleanup_txn(){")
cleanup_end = transaction.index("rollback(){", cleanup_start)
cleanup = transaction[cleanup_start:cleanup_end]
assert '[ -d \\"$PG\\" ] && [ ! -L \\"$PG\\" ]' in cleanup
assert '[ -d \\"$DIR\\" ] && [ ! -L \\"$DIR\\" ]' in cleanup
assert 'rm -rf \\"$TXN\\"' in cleanup and 'rm -rf \\"$STXN\\"' in cleanup
assert 'if [ \\"$_fx_txn_created\\" -eq 1 ]; then' in cleanup
assert 'if [ \\"$_fx_stxn_created\\" -eq 1 ]; then' in cleanup
assert '[ -d \\"$PG\\" ] && [ ! -L \\"$PG\\" ] || exit 41;' in transaction
assert '[ -d \\"$DIR\\" ] && [ ! -L \\"$DIR\\" ] || exit 44;' in transaction
assert '[ ! -e \\"$TXN\\" ] && [ ! -L \\"$TXN\\" ]' in transaction
assert '[ ! -e \\"$STXN\\" ] && [ ! -L \\"$STXN\\" ]' in transaction
assert 'rm -rf \\"$TXN\\" \\"$STXN\\" ||' not in transaction
assert transaction.count("if (!stellarFiles.containsKey(name)) continue;") == 1, "rollback must not touch Stellar files absent from an older/partial backup"
assert transaction.count("if (stellarFiles.containsKey(name))") >= 1, "commit loop must only replace staged Stellar files"
assert 'echo FX_DIA_RESTORE_COMMITTED' in transaction, "successful transaction must retain explicit commit marker"
rollback_loop_start = transaction.index("rollback(){")
rollback_loop_end = transaction.index("$_fx_config_swapped", rollback_loop_start)
rollback_loop = transaction[rollback_loop_start:rollback_loop_end]
assert "if (!stellarFiles.containsKey(name)) continue;" in rollback_loop, "rollback must not delete Stellar files absent from this backup"
assert "FX_DIA_RESTORE_ROLLBACK_FAILED TXN=" in transaction, "rollback failures must preserve recovery snapshots and report their paths"
q = chr(92) + '"'
assert ("if [ ! -d " + q + "$PG" + q + " ] || [ -L " + q + "$PG" + q + " ]") in transaction, "rollback must refuse to traverse a replaced PG directory"
assert ("if [ ! -d " + q + "$DIR" + q + " ] || [ -L " + q + "$DIR" + q + " ]") in transaction, "rollback must refuse to traverse a replaced Stellar directory"
assert helper.index("staged.put(entry.getKey(), cache);") < helper.index("new java.io.FileOutputStream(cache, false)"), "partially written staged files must be tracked for cleanup"
# Remote GitHub backups must preserve the 1 MiB product limit without
# misreporting successful uploads or forwarding tokens to untrusted download hosts.
assert "MAX_GITHUB_API_RESPONSE_BYTES = 2 * MAX_BACKUP_BYTES + 65536" in source
assert 'githubRequest(url, token, "PUT", body, false)' in source, \
    "successful Contents API PUT must not buffer the Base64 echo response"
assert "MAX_GITHUB_ERROR_BYTES = 65536" in source
assert "downloadRawGithubBackup(" in source and "FxDiaGithubBackupPolicy.isTrustedDownloadUrl(downloadUrl)" in source
assert "Base64.getMimeDecoder().decode(content)" in source
assert "setInstanceFollowRedirects(false)" in source, \
    "authenticated raw download must refuse redirects"
assert "MAX_BACKUP_BYTES" in source[source.index("private byte[] downloadRawGithubBackup"):source.index("private void githubDownload")]
assert '"raw.githubusercontent.com".equalsIgnoreCase(host)' in policy
assert "uri.getRawUserInfo() == null" in policy
assert "(port == -1 || port == 443)" in policy
assert '[ -d /data ] && [ ! -L /data ]' in module_reader, "module backup must reject symlinked /data ancestor"
assert '[ -d /data/adb ] && [ ! -L /data/adb ]' in module_reader, "module backup must reject symlinked /data/adb ancestor"
assert '[ -d /data ] && [ ! -L /data ]' in stellar_reader, "Stellar backup must reject symlinked /data ancestor"
assert '[ ! -L /data/local ]' in stellar_reader, "Stellar backup must reject symlinked /data/local"
assert '[ ! -e /data/local ] || [ -d /data/local ]' in stellar_reader, "Stellar backup must reject non-directory /data/local"
assert '[ ! -L /data/local/tmp ]' in stellar_reader, "Stellar backup must reject symlinked /data/local/tmp"
assert '[ ! -e /data/local/tmp ] || [ -d /data/local/tmp ]' in stellar_reader, "Stellar backup must reject non-directory /data/local/tmp"
assert '[ -d /data/local/tmp ] || exit 0' in stellar_reader, "missing Stellar parent must be treated as no existing backup state"
print("PASS: Dia backup restore stages private transactions, rejects symlinked parents and cleans only directories it created")
PY
