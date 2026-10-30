#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "77c2649822e9634de975b99b7f77a52c933c1884afdb399c153d226a6f6f4aad"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before input-method privacy patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("input-method privacy patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private boolean biometricHooksInstalled;\n",
     "    private boolean biometricHooksInstalled;\n    private boolean inputMethodHooksInstalled;\n")

once(
    "        final boolean hideFaceForPackage = privacyEnabled && target.hideFaceHw;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage\n"
    "                && !blockNotifListenForPackage && !hideNotifPermForPackage && !usageStatsForPackage && !accessibilityForPackage\n"
    "                && !hideFingerprintForPackage && !hideFaceForPackage\n"
    "                && !passiveLocationForPackage && !regionDiagForPackage && !mediaStoreForPackage) return;\n",
    "        final boolean hideFaceForPackage = privacyEnabled && target.hideFaceHw;\n"
    "        final boolean inputMethodForPackage = privacyEnabled && target.blockImeLogging;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage\n"
    "                && !blockNotifListenForPackage && !hideNotifPermForPackage && !usageStatsForPackage && !accessibilityForPackage\n"
    "                && !hideFingerprintForPackage && !hideFaceForPackage && !inputMethodForPackage\n"
    "                && !passiveLocationForPackage && !regionDiagForPackage && !mediaStoreForPackage) return;\n")

once("        if (hideFingerprintForPackage || hideFaceForPackage)\n"
     "            installBiometricPrivacyHooks(pkg, param.getClassLoader());\n",
     "        if (hideFingerprintForPackage || hideFaceForPackage)\n"
     "            installBiometricPrivacyHooks(pkg, param.getClassLoader());\n"
     "        if (inputMethodForPackage) installInputMethodPrivacyHooks(pkg);\n")

method = """    private boolean shouldHideInputMethods() {
        String pkg = currentPackage;
        return InputMethodPrivacyPolicy.shouldHideInputMethods(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private synchronized boolean installInputMethodPrivacyHooks(final String pkg) {
        if (inputMethodHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.view.inputmethod.InputMethodManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                String name = method.getName();
                if (!("getEnabledInputMethodList".equals(name)
                        || "getInputMethodList".equals(name)
                        || "getEnabledInputMethodSubtypeList".equals(name))) continue;
                if (!java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideInputMethods()
                                    ? java.util.Collections.emptyList() : chain.proceed());
                    installed++;
                } catch (Throwable ignored) {
                    logFx(Log.DEBUG, "input-method enumeration hook unavailable: " + name);
                }
            }
        } catch (Throwable ignored) {
            logFx(Log.DEBUG, "InputMethodManager API unavailable");
        }
        inputMethodHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in input-method privacy hooks installed=" + installed + " for " + pkg);
        return inputMethodHooksInstalled;
    }

"""
once("    private boolean shouldHideFingerprintHardware() {\n",
     method + "    private boolean shouldHideFingerprintHardware() {\n")

path.write_text(source)
expected = "abe61fe86118a3f0586dde534a7a638b596c61ba9cf7530479c8c79416f87bb4"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"input-method privacy source hash mismatch: {actual}")
print("API101 input-method privacy patch: PASS", actual)
