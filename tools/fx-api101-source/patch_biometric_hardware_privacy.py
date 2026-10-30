#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "5121fcc4ec803390c691154cdacbd3c4d1443bf26db45fa05a5fe5f6a2e64dcf"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before biometric hardware patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("biometric hardware patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private boolean accessibilityHooksInstalled;\n",
     "    private boolean accessibilityHooksInstalled;\n"
     "    private boolean biometricHooksInstalled;\n")

once(
    "        final boolean clipboardIsolateForPackage = privacyEnabled && target.clipboardIsolate && !target.clipboardReadBlock;\n",
    "        final boolean clipboardIsolateForPackage = privacyEnabled && target.clipboardIsolate && !target.clipboardReadBlock;\n"
    "        final boolean biometricForPackage = privacyEnabled && (target.hideFingerprintHw || target.hideFaceHw);\n")

once(
    "                && !clipboardIsolateForPackage && !sensorForPackage && !wifiScanForPackage",
    "                && !clipboardIsolateForPackage && !biometricForPackage && !sensorForPackage && !wifiScanForPackage")

once(
    "        if (clipboardIsolateForPackage) installClipboardIsolationHooks(pkg);\n",
    "        if (clipboardIsolateForPackage) installClipboardIsolationHooks(pkg);\n"
    "        if (biometricForPackage) installBiometricHardwarePrivacyHooks(param.getClassLoader(), pkg);\n")

method = """    private boolean shouldHideFingerprintHardware() {
        String pkg = currentPackage;
        UnifiedHookConfigParser.Target target = targets.get(pkg);
        return BiometricHardwarePrivacyPolicy.shouldHideFingerprint(
                privacyEnabled, processPackages.size(), pkg, target) && !NEVER.contains(pkg);
    }

    private boolean shouldHideFaceHardware() {
        String pkg = currentPackage;
        UnifiedHookConfigParser.Target target = targets.get(pkg);
        return BiometricHardwarePrivacyPolicy.shouldHideFace(
                privacyEnabled, processPackages.size(), pkg, target) && !NEVER.contains(pkg);
    }

    private synchronized boolean installBiometricHardwarePrivacyHooks(final ClassLoader appLoader,
                                                                       final String pkg) {
        if (biometricHooksInstalled) return true;
        int installed = 0;
        installed += installBiometricBooleanHooks("android.hardware.fingerprint.FingerprintManager", null,
                new String[]{"isHardwareDetected", "hasEnrolledFingerprints"}, true);
        installed += installBiometricBooleanHooks("android.hardware.face.FaceManager", null,
                new String[]{"isHardwareDetected", "hasEnrolledFaces"}, false);
        installed += installBiometricBooleanHooks("androidx.core.hardware.fingerprint.FingerprintManagerCompat",
                appLoader, new String[]{"isHardwareDetected", "hasEnrolledFingerprints"}, true);
        biometricHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in biometric hardware metadata hooks installed=" + installed + " for " + pkg);
        return biometricHooksInstalled;
    }

    private int installBiometricBooleanHooks(String className, ClassLoader loader,
                                             String[] methodNames, final boolean fingerprint) {
        int installed = 0;
        try {
            Class<?> type = Class.forName(className, false, loader);
            for (String name : methodNames) {
                try {
                    Method method;
                    try {
                        method = type.getDeclaredMethod(name);
                    } catch (NoSuchMethodException missing) {
                        method = type.getMethod(name);
                    }
                    if (method.getReturnType() != boolean.class
                            && method.getReturnType() != Boolean.class) continue;
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                boolean hide = fingerprint
                                        ? shouldHideFingerprintHardware() : shouldHideFaceHardware();
                                return hide ? Boolean.FALSE : chain.proceed();
                            });
                    installed++;
                } catch (NoSuchMethodException missing) {
                    logFx(Log.DEBUG, "biometric capability API unavailable: " + className + "." + name);
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "biometric capability hook unavailable: " + className + "." + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "biometric class unavailable: " + className);
        }
        return installed;
    }

"""
once("    /**\n     * Keep clipboard writes and reads inside this selected app process.",
     method + "    /**\n     * Keep clipboard writes and reads inside this selected app process.")

path.write_text(source)
actual = hashlib.sha256(path.read_bytes()).hexdigest()
print("API101 biometric hardware privacy patch: PASS", actual)
