#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
JAVA="$APP/java/de/privacyguard/adhook"
DIA="$JAVA/imported/dia"
MAIN="$JAVA/MainActivity.java"
MANIFEST="$APP/AndroidManifest.xml"
APPLICATION="$JAVA/FxHookApplication.java"
STORE="$DIA/FxDiaCrashStore.java"
RECORD="$DIA/FxDiaCrashRecord.java"
ACTIVITY="$DIA/FxDiaCrashReportActivity.java"
NATIVE_CAPTURE="$DIA/FxDiaNativeCrashCapture.java"
DUMP_DIRECTORY="$DIA/FxDiaCrashDumpDirectory.java"
DUMP_HOST_TEST="$ROOT/scripts/tests/FxDiaCrashDumpDirectoryHostTest.java"
JNI_WRAPPER="$APP/java/com/babyte/breakpad/BaByteBreakpad.java"
JNI_CALLBACK="$APP/java/com/babyte/breakpad/callback/NativeCrashCallback.java"
UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaCrashRecordTest.java"
HOST_JNI_TEST="$ROOT/scripts/tests/DiaBreakpadJniContractHostTest.java"
HOST_EXPORT_TEST="$ROOT/scripts/tests/DiaCrashExportFormatterHostTest.java"
WORKFLOW="$ROOT/.github/workflows/build-fx-adhook.yml"
POLICY="$DIA/FxDiaCrashCapturePolicy.java"
REDACTOR="$DIA/FxDiaCrashRedactor.java"
FORMATTER="$DIA/FxDiaCrashExportFormatter.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MAIN" "$MANIFEST" "$APPLICATION" "$STORE" "$RECORD" "$ACTIVITY" "$UNIT" "$POLICY" "$REDACTOR" "$FORMATTER" "$NATIVE_CAPTURE" "$DUMP_DIRECTORY" "$DUMP_HOST_TEST" "$JNI_WRAPPER" "$JNI_CALLBACK" "$HOST_JNI_TEST" "$HOST_EXPORT_TEST"; do
  [ -s "$file" ] || fail "Dia crash migration source missing: $file"
done
python3 - "$MAIN" "$MANIFEST" "$APPLICATION" "$STORE" "$RECORD" "$ACTIVITY" "$UNIT" "$REDACTOR" "$FORMATTER" "$DUMP_DIRECTORY" "$NATIVE_CAPTURE" "$JNI_WRAPPER" "$JNI_CALLBACK" "$WORKFLOW" "$HOST_EXPORT_TEST" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
main, manifest_path, application, store, record, activity, unit, redactor, formatter, dump_directory, native_capture, jni_wrapper, jni_callback, workflow, host_export_test = [
    Path(p).read_text(encoding="utf-8") for p in sys.argv[1:]
]
ns = "{http://schemas.android.com/apk/res/android}"
manifest = ET.parse(manifest_path).getroot()
declared = {node.attrib.get(ns + "name", ""): node for node in manifest.findall("./application/activity")}
name = ".imported.dia.FxDiaCrashReportActivity"
assert name in declared, "native Dia crash report Activity is not registered"
assert declared[name].attrib.get(ns + "exported") == "false", "crash report Activity must be private"
assert '"崩溃报告"' in main, "Dia crash report page is missing from navigation"
assert "FxDiaCrashReportActivity.class" in main, "Dia crash report menu does not route to native Activity"
assert "FxDiaCrashStore.hasPendingReport(this)" in main, "next app launch does not surface a prior crash"
assert "FxDiaCrashStore.install(this)" in application, "Application does not install Java crash capture"
assert "FxDiaNativeCrashCapture.install(this)" in application, "Application does not install original Dia Breakpad native capture"
assert "FxDiaCrashCapturePolicy.isEnabled" in store, "current and legacy capture switches must share one policy"
assert "remove(\"disable_java_crash_capture\").commit()" in store, "explicit re-enable must clear the legacy opt-out"
assert "button.setChecked(!enabled)" in activity, "capture UI must roll back when persistence fails"
for token in ("Thread.setDefaultUncaughtExceptionHandler", "delegate.uncaughtException(thread, error)",
              "AtomicFile", "startWrite()", "finishWrite(output)", "failWrite(output)",
              "FILE_NAME", "MAX_JSON_BYTES", "has_crash", "getFD().sync()",
              'json.optInt("schemaVersion", 0)', 'json.has("processName")', 'json.optString("stack", "")',
              'getSharedPreferences("digXposed"', '"encrypt_stack"'):
    assert token in store, f"crash store invariant missing: {token}"
assert "Process.killProcess(Process.myPid())" in store, "fallback fatal-exit path is missing"
assert "recordNativeCrash(" in store and "NATIVE_HANDLING" in store, "native callback is not persisted"
assert 'message.append("\\nMinidump: ")' in store, "minidump path is not saved"
assert "FxDiaNativeCrashCapture.install(application)" in store, "re-enable path does not install native capture"
assert 'System.loadLibrary("breakpad")' in jni_wrapper, "Breakpad JNI library is not loaded"
assert "private static final native void initBreakpadNative" in jni_wrapper, "original JNI method descriptor changed"
assert "onCrash(String minidumpPath, String nativeInfo" in jni_callback, "four-String JNI callback descriptor changed"
assert "FxDiaCrashStore.recordNativeCrash(app" in native_capture, "native callback is not connected to crash store"
assert "FxDiaCrashDumpDirectory.deleteDirectDump(app.getFilesDir(), minidumpPath)" in native_capture, "disabled native capture must discard only its new minidump"
assert "if (!FxDiaCrashStore.isCaptureEnabled(app))" in native_capture, "native callback must apply the unified Java/Native capture switch"
assert "Breakpad 原生处理器在当前进程内不能卸载" in activity, "UI must explain native callback behavior after disable"
assert "statusLine(this)" in activity, "native library availability is not shown"
assert "clearMinidumps(context)" in native_capture, "native dump directory has no explicit cleanup path"
assert "FxDiaCrashDumpDirectory.clear(context.getFilesDir())" in native_capture, "native dump cleanup does not use the path-safe deleter"
assert "if (!directory.exists() && !directory.mkdir() && !directory.isDirectory())" in dump_directory, "native dump cleanup must recreate a missing Breakpad output path"
assert "return directory.delete()" not in dump_directory, "native dump cleanup must preserve the output directory for the registered handler"
assert "remaining != null && remaining.length == 0" in dump_directory, "successful dump cleanup must verify all direct files were removed"
assert "public static boolean prune(File filesRoot, int maxFiles, long maxAgeMs, long nowMs)" in dump_directory, "native retention must use the path-safe helper"
assert "isDirectRegularFile(directory, entry)" in dump_directory, "prune must reject symlinked or nested dump entries"
assert "FxDiaCrashDumpDirectory.prune(filesRoot, 5" in native_capture, "native callback must use path-safe retention"
assert "synchronized (STORAGE_LOCK)" in store and store.count("synchronized (STORAGE_LOCK)") >= 7, "Java/Native crash reads, writes, settings, pending flags and clear must share one storage lock"
assert "if (!isCaptureEnabled(target))" in store, "native capture state must be rechecked after waiting for storage serialization"
assert "if (isCaptureEnabled(app))" in store, "Java capture state must be rechecked after waiting for storage serialization"
assert "if (context == null) return;" in store and "hasPendingReport(Context context)" in store, "pending-flag operations must tolerate missing context"
assert "FxDiaNativeCrashCapture.clearMinidumps(context)" in store, "crash clear action does not remove native minidumps"
assert "if (FxDiaCrashStore.clear(this))" in activity, "UI must only report a fully successful clear"
assert "可能已有部分文件被删除" in activity and "不会报告清除成功" in activity, "failed partial cleanup must not claim that the report was preserved or cleared"
assert "符号链接或意外子目录" in activity, "clear confirmation must disclose path-safety refusal"
for token in ("getCanonicalFile()", "entry.isFile()", "canonicalDirectory.equals(canonicalEntry.getParentFile())",
              "if (!entry.delete()) return false", "return target.delete() || !target.exists()",
              "public static boolean deleteDirectDump(File filesRoot, String minidumpPath)",
              "canonicalDirectory.equals(canonicalTarget.getParentFile())"):
    assert token in dump_directory, f"safe minidump deletion invariant missing: {token}"
assert "Java_com_babyte_breakpad_BaByteBreakpad_initBreakpadNative" in workflow, "workflow does not verify original JNI symbol"
assert "getPackageName()" in store and "Build.MODEL" in store, "process/device metadata is missing"
assert "MAX_STACK_CHARS" in record and "bounded(" in record, "crash fields are not size-bounded"
assert "schemaVersion == 0" in store and "file.getBaseFile().lastModified()" in store, "legacy unversioned Dia CrashInfo JSON must remain readable"
assert 'getSharedPreferences("digXposed"' in store, "legacy Dia shared crash preferences must be preserved"
assert "hexUtf8(" in record and "可逆，不是加密" in record, "HEX encoding must not be represented as encryption"
assert "FxDiaCrashExportFormatter.format(" in activity, "copy/share must use safe export formatter"
assert "FxDiaCrashRedactor.redact(record.format(false))" in formatter, "redact must run before optional HEX encoding"
assert "FxDiaCrashRecord.hexUtf8(safeStack)" in formatter, "HEX mode must encode only redacted stack content"
assert "hexExportRedactsOriginalStackBeforeEncoding" in unit, "JUnit must cover HEX stack secret redaction"
assert "hexUtf8(secret)" in host_export_test, "host test must detect reversible-HEX secret leaks"
assert "reportView.setText(record.format(" in activity, "local crash report view must retain raw diagnostic detail"
for token in ("Authorization", "KEY_VALUE", "QUERY_VALUE", "URL_USER_INFO", "BEARER", "JWT", "PEM_PRIVATE_KEY"):
    assert token in redactor, f"crash export credential redaction missing: {token}"
assert '"encrypt_stack"' in activity, "Dia original encrypt_stack preference must be preserved"
for token in ("ClipboardManager", "ClipData.newPlainText", "Intent.ACTION_SEND", "Intent.createChooser",
              "FxDiaCrashStore.clearPendingFlag(this)", "FxDiaCrashStore.setCaptureEnabled",
              "boolean hadPendingReport = FxDiaCrashStore.hasPendingReport(this)",
              "unreadablePendingReport = hadPendingReport && record == null",
              "crash.log 无法解析或超过 512 KiB 上限",
              "原始 crash.log 保留在 FX 私有 files 目录"):
    assert token in activity, f"native report operation missing: {token}"
for token in ("hexEncodingIsByteAccurateAndReversible", "recordFieldsAreBounded",
              "rawAndHexReportsAreDistinctAndClearlyLabeled",
              "explicitEnableRequiresBothLegacyAndCurrentVetoesToBeCleared"):
    assert token in unit, f"crash report unit coverage missing: {token}"
print("PASS: Dia Java + original Breakpad Native capture, private persistence, JNI ABI and status UI")
PY

for abi in arm64-v8a armeabi-v7a; do
  lib="$APP/jniLibs/$abi/libbreakpad.so"
  [ -s "$lib" ] || fail "original Dia Breakpad library was not staged for $abi"
  readelf -h "$lib" >/dev/null 2>&1 || fail "Breakpad library is not valid ELF for $abi"
  readelf -Ws "$lib" | grep -Fq 'Java_com_babyte_breakpad_BaByteBreakpad_initBreakpadNative' || fail "Breakpad JNI export missing for $abi"
done
if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT HUP INT TERM
  javac -d "$tmp" "$JNI_WRAPPER" "$JNI_CALLBACK" "$HOST_JNI_TEST" "$DUMP_DIRECTORY" "$DUMP_HOST_TEST" "$RECORD" "$REDACTOR" "$FORMATTER" "$HOST_EXPORT_TEST"
  java -cp "$tmp" com.babyte.breakpad.DiaBreakpadJniContractHostTest
  java -cp "$tmp" FxDiaCrashDumpDirectoryHostTest
  java -cp "$tmp" DiaCrashExportFormatterHostTest
else
  echo "SKIP: host JVM JNI reflection check (JDK unavailable); Android/JUnit source tests still retain the descriptor."
fi
