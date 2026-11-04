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
UNIT="$ROOT/adhook/app/src/test/java/de/privacyguard/adhook/imported/dia/FxDiaCrashRecordTest.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$MAIN" "$MANIFEST" "$APPLICATION" "$STORE" "$RECORD" "$ACTIVITY" "$UNIT"; do
  [ -s "$file" ] || fail "Dia crash migration source missing: $file"
done
python3 - "$MAIN" "$MANIFEST" "$APPLICATION" "$STORE" "$RECORD" "$ACTIVITY" "$UNIT" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
main, manifest_path, application, store, record, activity, unit = [
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
assert "FxDiaCrashStore.install(this)" in application, "Application does not install the crash handler"
for token in ("Thread.setDefaultUncaughtExceptionHandler", "delegate.uncaughtException(thread, error)",
              "AtomicFile", "startWrite()", "finishWrite(output)", "failWrite(output)",
              "FILE_NAME", "MAX_JSON_BYTES", "has_crash", "getFD().sync()"):
    assert token in store, f"crash store invariant missing: {token}"
assert "Process.killProcess(Process.myPid())" in store, "fallback fatal-exit path is missing"
assert "getPackageName()" in store and "Build.MODEL" in store, "process/device metadata is missing"
assert "MAX_STACK_CHARS" in record and "bounded(" in record, "crash fields are not size-bounded"
assert "hexUtf8(" in record and "可逆，不是加密" in record, "HEX encoding must not be represented as encryption"
for token in ("ClipboardManager", "ClipData.newPlainText", "Intent.ACTION_SEND", "Intent.createChooser",
              "FxDiaCrashStore.clearPendingFlag(this)", "FxDiaCrashStore.setCaptureEnabled",
              "boolean hadPendingReport = FxDiaCrashStore.hasPendingReport(this)",
              "unreadablePendingReport = hadPendingReport && record == null",
              "crash.log 无法解析或超过 512 KiB 上限",
              "原始 crash.log 保留在 FX 私有 files 目录"):
    assert token in activity, f"native report operation missing: {token}"
for token in ("hexEncodingIsByteAccurateAndReversible", "recordFieldsAreBounded",
              "rawAndHexReportsAreDistinctAndClearlyLabeled"):
    assert token in unit, f"crash report unit coverage missing: {token}"
print("PASS: Dia crash report UI, bounded private store, delegated fatal handler, HEX/copy/share behavior")
PY
