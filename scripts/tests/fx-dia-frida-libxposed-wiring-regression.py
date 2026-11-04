#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / "adhook/app/src/main/resources/META-INF/xposed/java_init.list"
HOOK = ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java"
LOADER = ROOT / "adhook/app/src/main/java/de/privacyguard/hook/DiaFridaGadgetLoader.java"
LEGACY = ROOT / "adhook/app/src/main/java/de/privacyguard/hook/DiaFridaTargetHook.java"

entry = ENTRY.read_text(encoding="utf-8").splitlines()
hook = HOOK.read_text(encoding="utf-8")
loader = LOADER.read_text(encoding="utf-8")
legacy = LEGACY.read_text(encoding="utf-8")

assert entry == ["de.privacyguard.adhook.AdVisibilityHook"], (
    "libXposed java_init must contain exactly the XposedModule entrypoint"
)
call = "DiaFridaGadgetLoader.loadForPackage(param.getApplicationInfo()"
assert call in hook, "registered libXposed entrypoint does not call the Dia Gadget loader"
assert hook.index(call) < hook.index("if (!adsForPackage && !memberDiagForPackage"), (
    "Dia Gadget loader must run independently of optional remote config"
)
assert "Application.getProcessName()" in hook, "loader must receive the actual isolated process name"
assert "public static void loadForPackage(ApplicationInfo info" in loader
for guard in (
    "ApplicationInfo.FLAG_DEBUGGABLE", "ApplicationInfo.FLAG_SYSTEM",
    "hasSymlinkComponent(rawNativeDir)", "MARKER_SCHEMA.equals(record.get(",
    "matchesProcess(markerProcesses, expectedProcess)",
    "constantEquals(record.get(\"library_sha256\"), libraryHash)",
    "constantEquals(record.get(\"config_sha256\"), configHash)",
    "System.load(gadget.getAbsolutePath())",
):
    assert guard in loader, f"loader security/activation guard missing: {guard}"
assert "DiaFridaGadgetLoader.loadForPackage(" in legacy, "legacy adapter no longer delegates"
assert "IXposedHookLoadPackage" in legacy, "legacy LSPosed adapter was dropped"
print("PASS: Dia Gadget loader is reachable from modern libXposed and legacy LSPosed")
