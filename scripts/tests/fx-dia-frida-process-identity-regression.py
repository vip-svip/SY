#!/usr/bin/env python3
"""Ensure Frida only attaches to processes whose package UID still matches."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java").read_text(encoding="utf-8")


def body(signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


picker = body("private void chooseTargetProcesses()", "private void loadOriginalExamples()")
inject = body("private void injectScript()", "private String sessionLogPath()")

assert "getApplicationInfo(requestedPackage, 0)" in picker and "targetUid = targetInfo.uid" in picker
assert "targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE" in picker
assert "targetInfo.flags & ApplicationInfo.FLAG_SYSTEM" in picker
assert '"; uid=" + targetUid' in picker, "process enumeration must be bound to the currently installed target UID"
assert '/proc/$pid/status' in picker and 'Uid:' in picker and '{print $2; exit}' in picker, "process picker must reject PID/name matches whose current UID differs"
assert picker.index("getApplicationInfo(requestedPackage, 0)") < picker.index("RootAccess.execute(command, 15000L"), "current package identity must be captured before enumerating processes"

# A package may be uninstalled/reinstalled while Root enumerates processes.
# The UI must re-resolve the package before presenting the captured PID snapshot.
callback_guard = picker.index("if (result.exitCode != 0 || result.output == null)")
identity_recheck = picker.index("getApplicationInfo(requestedPackage, 0)", callback_guard)
assert callback_guard >= 0 and identity_recheck > callback_guard, \
    "process scan callback must re-resolve the installed target before showing PIDs"
assert "currentTarget.uid != targetUid" in picker, \
    "reinstalled target with a different UID must discard the old PID snapshot"
assert "(currentTarget.flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0" in picker
assert "(currentTarget.flags & ApplicationInfo.FLAG_SYSTEM) != 0" in picker
assert "processPickerGeneration" in picker and "operationGeneration != processPickerGeneration" in picker, \
    "late process scan callbacks must be discarded after target selection changes"
target_picker = body("private void showTargetPicker(List<Target> targets)", "private void clearPendingProcessPickerState()")
assert "processPickerGeneration++;" in target_picker, \
    "selecting a new package must invalidate any in-flight process picker request"
assert "processPickerOpen = false;" in target_picker and "clearPendingProcessPickerState();" in target_picker, \
    "switching target must clear staged process selection from the previous target"

assert "targetUid = targetInfo.uid" in inject
assert '"; target_uid=" + targetUid' in inject, "injection command must carry the freshly resolved package UID"
assert 'proc_uid=$(awk' in inject and '/proc/$pid/status' in inject
assert 'skipped-uid-mismatch-pid=$pid' in inject, "UID mismatch must skip the PID rather than attempt injection"
uid_check = inject.index('proc_uid=$(awk')
attach = inject.index(' -p \\"$pid\\" -s ')
assert uid_check < attach, "current process UID must be verified before invoking frida-inject"
assert r'case \"$proc\" in \"$pkg\"|\"$pkg\":*)' in inject, "package/process-name scope check must remain"
assert "base=/data/adb/privacyguard" in inject and "for path in /data /data/adb /data/adb/privacyguard" in inject, \
    "Frida script staging must validate each parent state directory"
assert "unsafe-frida-state-symlink=$path" in inject and "unsafe-frida-session-file" in inject, \
    "Frida script staging must reject symlinked state and destination paths"
assert 'tmp=$(mktemp ' in inject and 'base64 -d > ' in inject and 'mv -f ' in inject, \
    "Frida script source must be staged privately and atomically replaced"
assert 'unsafe-frida-log-path' in inject and 'chmod 600' in inject, \
    "Frida session logs must remain private and regular files"
viewer = body("private void showSessionLog()", "private void showMonitorEvents()")
assert "[ ! -L " in viewer and "[ -f " in viewer and "[ -s " in viewer, \
    "session log viewer must refuse symlink and non-regular log targets"
assert r'\\\"' not in inject, "Java command builder must emit shell quoting, not literal backslash-quote characters"
assert r'[ ! -L \"$log\" ]' in inject, "session log symlink guard must keep a syntactically complete test bracket"
assert "trap '[ -z " in inject and "|| rm -f " in inject and "' EXIT" in inject, \
    "temporary Frida script cleanup must tolerate tmp being cleared after atomic replace"
assert "trap 'exit 129' HUP" in inject and "trap 'exit 130' INT" in inject and "trap 'exit 143' TERM" in inject, \
    "signal handlers must exit into the single EXIT cleanup path"
print("PASS: Frida selection/injection revalidate package UID and use private, symlink-safe script/log paths")
