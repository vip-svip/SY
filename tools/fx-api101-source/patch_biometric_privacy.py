#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "5121fcc4ec803390c691154cdacbd3c4d1443bf26db45fa05a5fe5f6a2e64dcf"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before biometric privacy patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("biometric privacy patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private boolean accessibilityHooksInstalled;\n",
     "    private boolean accessibilityHooksInstalled;\n    private boolean biometricHooksInstalled;\n")

once(
    "        final boolean accessibilityForPackage = privacyEnabled && target.a11yHide;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage\n"
    "                && !blockNotifListenForPackage && !hideNotifPermForPackage && !usageStatsForPackage && !accessibilityForPackage\n"
    "                && !passiveLocationForPackage && !regionDiagForPackage && !mediaStoreForPackage) return;\n",
    "        final boolean accessibilityForPackage = privacyEnabled && target.a11yHide;\n"
    "        final boolean hideFingerprintForPackage = privacyEnabled && target.hideFingerprintHw;\n"
    "        final boolean hideFaceForPackage = privacyEnabled && target.hideFaceHw;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage\n"
    "                && !blockNotifListenForPackage && !hideNotifPermForPackage && !usageStatsForPackage && !accessibilityForPackage\n"
    "                && !hideFingerprintForPackage && !hideFaceForPackage\n"
    "                && !passiveLocationForPackage && !regionDiagForPackage && !mediaStoreForPackage) return;\n")

once("        if (accessibilityForPackage) installAccessibilityPrivacyHooks(pkg);\n",
     "        if (accessibilityForPackage) installAccessibilityPrivacyHooks(pkg);\n"
     "        if (hideFingerprintForPackage || hideFaceForPackage)\n"
     "            installBiometricPrivacyHooks(pkg, param.getClassLoader());\n")

method = """    private boolean shouldHideFingerprintHardware() {
        String pkg = currentPackage;
        return BiometricPrivacyPolicy.shouldHideFingerprint(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private boolean shouldHideFaceHardware() {
        String pkg = currentPackage;
        return BiometricPrivacyPolicy.shouldHideFace(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private boolean shouldReportNoBiometricHardware() {
        String pkg = currentPackage;
        return BiometricPrivacyPolicy.shouldReportNoBiometricHardware(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private synchronized boolean installBiometricPrivacyHooks(final String pkg, ClassLoader appClassLoader) {
        if (biometricHooksInstalled) return true;
        int installed = 0;
        if (shouldHideFingerprintHardware()) {
            for (String className : new String[]{
                    "android.hardware.fingerprint.FingerprintManager",
                    "androidx.core.hardware.fingerprint.FingerprintManagerCompat"}) {
                try {
                    ClassLoader loader = className.startsWith("androidx.") ? appClassLoader : null;
                    Class<?> type = Class.forName(className, false, loader);
                    for (Method method : type.getDeclaredMethods()) {
                        String name = method.getName();
                        if (!("isHardwareDetected".equals(name) || "hasEnrolledFingerprints".equals(name))
                                || method.getReturnType() != boolean.class) continue;
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> shouldHideFingerprintHardware() ? false : chain.proceed());
                        installed++;
                    }
                } catch (Throwable ignored) {
                    logFx(Log.DEBUG, "fingerprint hardware API unavailable: " + className);
                }
            }
        }
        if (shouldHideFaceHardware()) {
            try {
                Class<?> type = Class.forName("android.hardware.face.FaceManager", false, null);
                for (Method method : type.getDeclaredMethods()) {
                    String name = method.getName();
                    if (!("isHardwareDetected".equals(name) || "hasEnrolledFaces".equals(name))
                            || method.getReturnType() != boolean.class) continue;
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> shouldHideFaceHardware() ? false : chain.proceed());
                    installed++;
                }
            } catch (Throwable ignored) {
                logFx(Log.DEBUG, "FaceManager hardware APIs unavailable");
            }
        }
        try {
            Class<?> type = Class.forName("android.hardware.biometrics.BiometricManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"canAuthenticate".equals(method.getName()) || method.getReturnType() != int.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldReportNoBiometricHardware() ? 12 : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {
            logFx(Log.DEBUG, "BiometricManager API unavailable");
        }
        biometricHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in biometric hardware privacy hooks installed=" + installed + " for " + pkg);
        return biometricHooksInstalled;
    }

"""
once("    private boolean shouldHideActiveNotifications() {\n",
     method + "    private boolean shouldHideActiveNotifications() {\n")

path.write_text(source)
expected = "77c2649822e9634de975b99b7f77a52c933c1884afdb399c153d226a6f6f4aad"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"biometric privacy source hash mismatch: {actual}")
print("API101 biometric hardware privacy patch: PASS", actual)
