#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "654d39cea7bb3c1c19bebf1dbd56808e395a66de7edc161d7d12d7c8dcb3fdbf"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before audio fingerprint patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("audio fingerprint patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private boolean microphoneHardwareHooksInstalled;\n",
     "    private boolean microphoneHardwareHooksInstalled;\n    private boolean audioFingerprintHooksInstalled;\n")

once(
    "        final boolean micHwHideForPackage = privacyEnabled && target.micHwHide;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !passiveLocationForPackage && !regionDiagForPackage\n"
    "                && !mediaStoreForPackage) return;\n",
    "        final boolean micHwHideForPackage = privacyEnabled && target.micHwHide;\n"
    "        final boolean audioFpForPackage = privacyEnabled && target.audioFpBlock;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage && !passiveLocationForPackage && !regionDiagForPackage\n"
    "                && !mediaStoreForPackage) return;\n")

once("        if (micHwHideForPackage) installMicrophoneHardwarePrivacyHooks(pkg);\n",
     "        if (micHwHideForPackage) installMicrophoneHardwarePrivacyHooks(pkg);\n"
     "        if (audioFpForPackage && !micBlockForPackage) installAudioFingerprintPrivacyHooks(pkg);\n")

method = """    /** Apply bounded low-amplitude noise to selected app capture buffers after a successful read. */
    private boolean shouldPerturbAudioSamples() {
        String pkg = currentPackage;
        UnifiedHookConfigParser.Target target = targets.get(pkg);
        return AudioFingerprintPolicy.shouldPerturbSamples(
                privacyEnabled, processPackages.size(), pkg, target) && !NEVER.contains(pkg);
    }

    private synchronized boolean installAudioFingerprintPrivacyHooks(final String pkg) {
        if (audioFingerprintHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.media.AudioRecord", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"read".equals(method.getName()) || method.getReturnType() != int.class) continue;
                Class<?>[] parameters = method.getParameterTypes();
                if (parameters.length < 2) continue;
                Class<?> bufferType = parameters[0];
                boolean supported = bufferType == byte[].class || bufferType == short[].class
                        || bufferType == float[].class || java.nio.ByteBuffer.class.isAssignableFrom(bufferType);
                if (!supported) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                if (!shouldPerturbAudioSamples()) return chain.proceed();
                                Object result = chain.proceed();
                                if (!(result instanceof Integer) || ((Integer) result) <= 0) return result;
                                int count = (Integer) result;
                                java.util.List<Object> args = chain.getArgs();
                                Object buffer = args.get(0);
                                if (buffer instanceof byte[]) {
                                    byte[] data = (byte[]) buffer;
                                    int offset = args.size() >= 3 && args.get(1) instanceof Integer ? (Integer) args.get(1) : 0;
                                    if (offset < 0 || offset >= data.length) return result;
                                    count = Math.min(count, data.length - offset);
                                    for (int i = offset; i < offset + count; i++)
                                        data[i] = (byte) (data[i] + java.util.concurrent.ThreadLocalRandom.current().nextInt(3) - 1);
                                } else if (buffer instanceof short[]) {
                                    short[] data = (short[]) buffer;
                                    int offset = args.size() >= 3 && args.get(1) instanceof Integer ? (Integer) args.get(1) : 0;
                                    if (offset < 0 || offset >= data.length) return result;
                                    count = Math.min(count, data.length - offset);
                                    for (int i = offset; i < offset + count; i++) {
                                        int value = data[i] + java.util.concurrent.ThreadLocalRandom.current().nextInt(61) - 30;
                                        data[i] = (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, value));
                                    }
                                } else if (buffer instanceof float[]) {
                                    float[] data = (float[]) buffer;
                                    int offset = args.size() >= 3 && args.get(1) instanceof Integer ? (Integer) args.get(1) : 0;
                                    if (offset < 0 || offset >= data.length) return result;
                                    count = Math.min(count, data.length - offset);
                                    for (int i = offset; i < offset + count; i++) {
                                        float value = data[i] + (java.util.concurrent.ThreadLocalRandom.current().nextFloat() - 0.5f) * 0.004f;
                                        data[i] = Math.max(-1.0f, Math.min(1.0f, value));
                                    }
                                } else if (buffer instanceof java.nio.ByteBuffer) {
                                    java.nio.ByteBuffer data = ((java.nio.ByteBuffer) buffer).duplicate();
                                    int end = data.position();
                                    int start = Math.max(0, end - Math.min(count, end));
                                    for (int i = start; i < end; i++)
                                        data.put(i, (byte) (data.get(i) + java.util.concurrent.ThreadLocalRandom.current().nextInt(3) - 1));
                                }
                                return result;
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "AudioRecord fingerprint overload unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "AudioRecord unavailable; audio fingerprint privacy fails open");
            return false;
        }
        audioFingerprintHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in audio fingerprint sample perturbation installed=" + installed + " for " + pkg);
        return audioFingerprintHooksInstalled;
    }

"""
once("    /** Hide input-device enumeration for the selected app only; no system-wide audio routing is changed. */\n",
     method + "    /** Hide input-device enumeration for the selected app only; no system-wide audio routing is changed. */\n")

path.write_text(source)
actual = hashlib.sha256(path.read_bytes()).hexdigest()
print("API101 audio fingerprint privacy patch: PASS", actual)
