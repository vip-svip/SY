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

assert "getApplicationInfo(targetPackage, 0)" in picker and "targetUid = targetInfo.uid" in picker
assert "targetInfo.flags & ApplicationInfo.FLAG_DEBUGGABLE" in picker
assert "targetInfo.flags & ApplicationInfo.FLAG_SYSTEM" in picker
assert '"; uid=" + targetUid' in picker, "process enumeration must be bound to the currently installed target UID"
assert '/proc/$pid/status' in picker and 'Uid:' in picker and '{print $2; exit}' in picker, \\
    "process picker must reject PID/name matches whose current UID differs"
assert picker.index("getApplicationInfo(targetPackage, 0)") < picker.index("runRoot(command"), \
    "current package identity must be captured before enumerating processes"

assert "targetUid = targetInfo.uid" in inject
assert '"target_uid=" + targetUid' in inject, "injection command must carry the freshly resolved package UID"
assert 'proc_uid=$(awk' in inject and '/proc/$pid/status' in inject
assert 'skipped-uid-mismatch-pid=$pid' in inject, "UID mismatch must skip the PID rather than attempt injection"
uid_check = inject.index('proc_uid=$(awk')
attach = inject.index(' -p \\"$pid\\" -s ')
assert uid_check < attach, "current process UID must be verified before invoking frida-inject"
assert 'case "$proc" in "$pkg"|"$pkg":*)' in inject, "package/process-name scope check must remain"
print("PASS: Frida process selection and injection revalidate debuggable package UID before PID attach")
