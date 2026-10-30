#!/usr/bin/env python3
from pathlib import Path
import hashlib
path=Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source=path.read_text()
base="155423b0452ba5866449695bc21795622f2bf5bd44a54ec121911c1a982ec4b3"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=base: raise SystemExit(f"unexpected microphone-privacy source: {actual}")
def once(old,new):
 global source
 if source.count(old)!=1: raise SystemExit("passive-location patch anchor mismatch: "+old[:100])
 source=source.replace(old,new,1)
once("    private boolean microphoneHooksInstalled;\n","    private boolean microphoneHooksInstalled;\n    private boolean passiveLocationHooksInstalled;\n")
once(
"        final boolean micBlockForPackage = privacyEnabled && target.micBlock;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage) return;\n",
"        final boolean micBlockForPackage = privacyEnabled && target.micBlock;\n"
"        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage && !passiveLocationForPackage) return;\n")
once("        if (micBlockForPackage) installMicrophoneReadBlockHooks(pkg);\n",
     "        if (micBlockForPackage) installMicrophoneReadBlockHooks(pkg);\n        if (passiveLocationForPackage) installPassiveLocationPrivacyHooks(pkg);\n")
once(
"                + \" sdk=\" + Build.VERSION.SDK_INT);\n",
"                + \" passiveLocationHide=\" + passiveLocationForPackage + \" sdk=\" + Build.VERSION.SDK_INT);\n")
method="""    /** Hide cached last-known LocationManager results; live location updates are not blocked. */
    private synchronized boolean installPassiveLocationPrivacyHooks(final String pkg) {
        if (passiveLocationHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.location.LocationManager", false, null);
            Class<?> locationType = Class.forName("android.location.Location", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"getLastKnownLocation".equals(method.getName())
                        || !locationType.isAssignableFrom(method.getReturnType())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (LocationPrivacyPolicy.shouldHideLastKnownLocation(privacyEnabled,
                                        processPackages.size(), activePackage, active)
                                        && !NEVER.contains(activePackage)) return null;
                                return chain.proceed();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "LocationManager last-known hook unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "LocationManager unavailable; passive-location privacy fails open");
            return false;
        }
        passiveLocationHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in last-known location redaction installed=" + installed + " for " + pkg);
        return passiveLocationHooksInstalled;
    }

"""
once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n",method+"    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")
path.write_text(source)
expected="130da4f15b96def49dfb8e5f83170f38d6aa3b847e6afc284b8d894ab4d892cf"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=expected: raise SystemExit(f"passive-location source hash mismatch: {actual}")
print("API101 cached passive-location privacy patch: PASS",actual)
