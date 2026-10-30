#!/usr/bin/env python3
from pathlib import Path
import hashlib
path=Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source=path.read_text()
base="550aef6699758c72c6c1237a521bbf022ca7f66e33b820a1b5e4c04007f21368"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=base: raise SystemExit(f"unexpected camera-privacy source: {actual}")
def once(old,new):
 global source
 if source.count(old)!=1: raise SystemExit("microphone patch anchor mismatch: "+old[:100])
 source=source.replace(old,new,1)
once("    private boolean cameraIdHooksInstalled;\n","    private boolean cameraIdHooksInstalled;\n    private boolean microphoneHooksInstalled;\n")
once(
"        final boolean cameraIdForPackage = privacyEnabled && target.cameraIdHide;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage) return;\n",
"        final boolean cameraIdForPackage = privacyEnabled && target.cameraIdHide;\n"
"        final boolean micBlockForPackage = privacyEnabled && target.micBlock;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage) return;\n")
once("        if (cameraIdForPackage) installCameraIdPrivacyHooks(pkg);\n",
     "        if (cameraIdForPackage) installCameraIdPrivacyHooks(pkg);\n        if (micBlockForPackage) installMicrophoneReadBlockHooks(pkg);\n")
once(
"                \" cameraIdHide=\" + cameraIdForPackage + \" sdk=\" + Build.VERSION.SDK_INT);\n",
"                \" cameraIdHide=\" + cameraIdForPackage + \" micBlock=\" + micBlockForPackage\n"
"                + \" sdk=\" + Build.VERSION.SDK_INT);\n")
method="""    /** Silence selected AudioRecord read buffers; MediaRecorder/native capture are not covered. */
    private synchronized boolean installMicrophoneReadBlockHooks(final String pkg) {
        if (microphoneHooksInstalled) return true;
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
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (!AudioPrivacyPolicy.shouldSilenceAudioRecord(privacyEnabled,
                                        processPackages.size(), activePackage, active)
                                        || NEVER.contains(activePackage)) return chain.proceed();
                                java.util.List<Object> args = chain.getArgs();
                                Object buffer = args.get(0);
                                int offset = parameters.length >= 3 && args.get(1) instanceof Integer
                                        ? (Integer) args.get(1) : 0;
                                int requested = parameters.length >= 3 && args.get(2) instanceof Integer
                                        ? (Integer) args.get(2)
                                        : (args.size() >= 2 && args.get(1) instanceof Integer ? (Integer) args.get(1) : 0);
                                if (requested <= 0) return 0;
                                if (buffer instanceof byte[]) {
                                    byte[] data = (byte[]) buffer;
                                    if (offset < 0 || offset > data.length) return 0;
                                    int count = Math.min(requested, data.length - offset);
                                    java.util.Arrays.fill(data, offset, offset + count, (byte) 0);
                                    return count;
                                }
                                if (buffer instanceof short[]) {
                                    short[] data = (short[]) buffer;
                                    if (offset < 0 || offset > data.length) return 0;
                                    int count = Math.min(requested, data.length - offset);
                                    java.util.Arrays.fill(data, offset, offset + count, (short) 0);
                                    return count;
                                }
                                if (buffer instanceof float[]) {
                                    float[] data = (float[]) buffer;
                                    if (offset < 0 || offset > data.length) return 0;
                                    int count = Math.min(requested, data.length - offset);
                                    java.util.Arrays.fill(data, offset, offset + count, 0.0f);
                                    return count;
                                }
                                if (buffer instanceof java.nio.ByteBuffer) {
                                    java.nio.ByteBuffer data = (java.nio.ByteBuffer) buffer;
                                    int count = Math.min(requested, data.remaining());
                                    try {
                                        for (int i = 0; i < count; i++) data.put((byte) 0);
                                        return count;
                                    } catch (Throwable readOnlyBuffer) {
                                        return 0;
                                    }
                                }
                                return 0;
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "AudioRecord read overload unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "AudioRecord unavailable; microphone privacy fails open");
            return false;
        }
        microphoneHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in AudioRecord microphone read suppression installed=" + installed + " for " + pkg);
        return microphoneHooksInstalled;
    }

"""
once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n",method+"    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")
path.write_text(source)
expected="155423b0452ba5866449695bc21795622f2bf5bd44a54ec121911c1a982ec4b3"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=expected: raise SystemExit(f"microphone privacy source hash mismatch: {actual}")
print("API101 AudioRecord microphone privacy patch: PASS",actual)
