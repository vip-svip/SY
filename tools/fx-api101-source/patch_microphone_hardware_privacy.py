#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "ebaec0c3089990a3c2994518abda42cd4f57bf5c5e6f6957e67c0ec4d63d5e1a"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before mic hardware patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("mic hardware patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private boolean microphoneHooksInstalled;\n",
     "    private boolean microphoneHooksInstalled;\n    private boolean microphoneHardwareHooksInstalled;\n")

once(
    "        final boolean micBlockForPackage = privacyEnabled && target.micBlock;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !passiveLocationForPackage && !regionDiagForPackage\n"
    "                && !mediaStoreForPackage) return;\n",
    "        final boolean micBlockForPackage = privacyEnabled && target.micBlock;\n"
    "        final boolean micHwHideForPackage = privacyEnabled && target.micHwHide;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !passiveLocationForPackage && !regionDiagForPackage\n"
    "                && !mediaStoreForPackage) return;\n")

once("        if (micBlockForPackage) installMicrophoneReadBlockHooks(pkg);\n",
     "        if (micBlockForPackage) installMicrophoneReadBlockHooks(pkg);\n"
     "        if (micHwHideForPackage) installMicrophoneHardwarePrivacyHooks(pkg);\n")

method = """    /** Hide input-device enumeration for the selected app only; no system-wide audio routing is changed. */
    private boolean shouldHideMicrophoneHardware() {
        String pkg = currentPackage;
        UnifiedHookConfigParser.Target target = targets.get(pkg);
        return MicrophoneHardwarePrivacyPolicy.shouldHideInputDevices(
                privacyEnabled, processPackages.size(), pkg, target) && !NEVER.contains(pkg);
    }

    private synchronized boolean installMicrophoneHardwarePrivacyHooks(final String pkg) {
        if (microphoneHardwareHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> managerType = Class.forName("android.media.AudioManager", false, null);
            Method getDevices = managerType.getDeclaredMethod("getDevices", int.class);
            hook(getDevices).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                    .intercept(chain -> {
                        if (!shouldHideMicrophoneHardware()) return chain.proceed();
                        Object flagArg = chain.getArgs().get(0);
                        if (!(flagArg instanceof Integer) || ((((Integer) flagArg) & 1) == 0))
                            return chain.proceed();
                        Object original = chain.proceed();
                        if (original == null || !original.getClass().isArray()) return original;
                        int length = java.lang.reflect.Array.getLength(original);
                        java.util.List<Object> visible = new java.util.ArrayList<>();
                        for (int i = 0; i < length; i++) {
                            Object device = java.lang.reflect.Array.get(original, i);
                            boolean input = false;
                            if (device != null) {
                                try {
                                    Object sourceFlag = device.getClass().getMethod("isSource").invoke(device);
                                    input = Boolean.TRUE.equals(sourceFlag);
                                } catch (Throwable ignored) {
                                    // Unknown device type is retained: fail open.
                                }
                            }
                            if (!input) visible.add(device);
                        }
                        Object filtered = java.lang.reflect.Array.newInstance(
                                original.getClass().getComponentType(), visible.size());
                        for (int i = 0; i < visible.size(); i++)
                            java.lang.reflect.Array.set(filtered, i, visible.get(i));
                        return filtered;
                    });
            installed++;
        } catch (Throwable t) {
            logFx(Log.DEBUG, "AudioManager input-device enumeration hook unavailable");
        }

        try {
            Class<?> recordType = Class.forName("android.media.AudioRecord", false, null);
            for (Method method : recordType.getDeclaredMethods()) {
                if (method.getParameterTypes().length != 0) continue;
                if (!"getRoutedDevice".equals(method.getName())
                        && !"getActiveMicrophones".equals(method.getName())) continue;
                final String name = method.getName();
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldHideMicrophoneHardware()) return chain.proceed();
                                if ("getRoutedDevice".equals(name)) return null;
                                return java.util.Collections.emptyList();
                            });
                    installed++;
                } catch (Throwable ignored) {
                    logFx(Log.DEBUG, "AudioRecord hardware metadata hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.DEBUG, "AudioRecord hardware metadata APIs unavailable");
        }

        microphoneHardwareHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in microphone hardware enumeration privacy hooks installed=" + installed + " for " + pkg);
        return microphoneHardwareHooksInstalled;
    }

"""
once("    /** Silence selected AudioRecord read buffers; MediaRecorder/native capture are not covered. */\n",
     method + "    /** Silence selected AudioRecord read buffers; MediaRecorder/native capture are not covered. */\n")

path.write_text(source)
actual = hashlib.sha256(path.read_bytes()).hexdigest()
print("API101 microphone hardware privacy patch: PASS", actual)
