#!/usr/bin/env python3
from pathlib import Path
import hashlib
path=Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source=path.read_text()
base="0d8d93d911d89e9a084f6160511cfc2dac40915652091fc9ac36ffeec3625c48"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=base: raise SystemExit(f"unexpected radio-privacy source: {actual}")
def once(old,new):
 global source
 if source.count(old)!=1: raise SystemExit("camera patch anchor mismatch: "+old[:100])
 source=source.replace(old,new,1)
once("    private boolean cellInfoHooksInstalled;\n","    private boolean cellInfoHooksInstalled;\n    private boolean cameraIdHooksInstalled;\n")
once(
"        final boolean cellInfoForPackage = privacyEnabled && target.cellInfoHide;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage) return;\n",
"        final boolean cellInfoForPackage = privacyEnabled && target.cellInfoHide;\n"
"        final boolean cameraIdForPackage = privacyEnabled && target.cameraIdHide;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage) return;\n")
once("        if (cellInfoForPackage) installCellInfoPrivacyHooks(pkg);\n",
     "        if (cellInfoForPackage) installCellInfoPrivacyHooks(pkg);\n        if (cameraIdForPackage) installCameraIdPrivacyHooks(pkg);\n")
once(
"                \" wifiScanHide=\" + wifiScanForPackage + \" cellInfoHide=\" + cellInfoForPackage +\n"
"                \" sdk=\" + Build.VERSION.SDK_INT);\n",
"                \" wifiScanHide=\" + wifiScanForPackage + \" cellInfoHide=\" + cellInfoForPackage +\n"
"                \" cameraIdHide=\" + cameraIdForPackage + \" sdk=\" + Build.VERSION.SDK_INT);\n")
method="""    /** Hide camera enumeration for a selected app; this does not block known-ID openCamera calls. */
    private synchronized boolean installCameraIdPrivacyHooks(final String pkg) {
        if (cameraIdHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.hardware.camera2.CameraManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"getCameraIdList".equals(method.getName()) || method.getParameterTypes().length != 0
                        || method.getReturnType() != String[].class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (CameraPrivacyPolicy.shouldHideCameraIds(privacyEnabled,
                                        processPackages.size(), activePackage, active)
                                        && !NEVER.contains(activePackage)) return new String[0];
                                return chain.proceed();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "CameraManager camera-ID hook unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "CameraManager unavailable; camera-ID privacy fails open");
            return false;
        }
        cameraIdHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in camera-ID enumeration redaction installed=" + installed + " for " + pkg);
        return cameraIdHooksInstalled;
    }

"""
once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n",method+"    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")
path.write_text(source)
expected="550aef6699758c72c6c1237a521bbf022ca7f66e33b820a1b5e4c04007f21368"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=expected: raise SystemExit(f"camera privacy source hash mismatch: {actual}")
print("API101 camera-ID privacy patch: PASS",actual)
