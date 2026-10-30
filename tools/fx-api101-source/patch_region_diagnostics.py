#!/usr/bin/env python3
from pathlib import Path
import hashlib
path=Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source=path.read_text()
base="130da4f15b96def49dfb8e5f83170f38d6aa3b847e6afc284b8d894ab4d892cf"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=base: raise SystemExit(f"unexpected passive-location source: {actual}")
def once(old,new):
 global source
 if source.count(old)!=1: raise SystemExit("region diagnostic patch anchor mismatch: "+old[:100])
 source=source.replace(old,new,1)
once("    private boolean passiveLocationHooksInstalled;\n","    private boolean passiveLocationHooksInstalled;\n    private boolean regionDiagnosticsInstalled;\n")
once(
"        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage && !passiveLocationForPackage) return;\n",
"        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
"        final boolean regionDiagForPackage = target.regionDiag;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage && !passiveLocationForPackage && !regionDiagForPackage) return;\n")
once("        if (passiveLocationForPackage) installPassiveLocationPrivacyHooks(pkg);\n",
     "        if (passiveLocationForPackage) installPassiveLocationPrivacyHooks(pkg);\n        if (regionDiagForPackage) installRegionCompatibilityDiagnostics(pkg);\n")
once(
"                + \" passiveLocationHide=\" + passiveLocationForPackage + \" sdk=\" + Build.VERSION.SDK_INT);\n",
"                + \" passiveLocationHide=\" + passiveLocationForPackage + \" regionDiag=\" + regionDiagForPackage\n"
"                + \" sdk=\" + Build.VERSION.SDK_INT);\n")
method="""    /** Observe local locale versus SIM/network country metadata without changing either value. */
    private synchronized boolean installRegionCompatibilityDiagnostics(final String pkg) {
        if (regionDiagnosticsInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.telephony.TelephonyManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                String name = method.getName();
                if (!("getSimCountryIso".equals(name) || "getNetworkCountryIso".equals(name))
                        || method.getParameterTypes().length != 0 || method.getReturnType() != String.class) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                Object result = chain.proceed();
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (RegionCompatibilityPolicy.shouldObserveRegion(
                                        processPackages.size(), activePackage, active)) {
                                    String iso = result instanceof String ? ((String) result).trim() : "";
                                    String localeCountry = java.util.Locale.getDefault().getCountry();
                                    boolean comparable = !iso.isEmpty() && !localeCountry.isEmpty();
                                    boolean mismatch = comparable && !iso.equalsIgnoreCase(localeCountry);
                                    logFx(Log.INFO, "read-only region compatibility source=" + name
                                            + " comparable=" + comparable + " mismatch=" + mismatch);
                                }
                                return result;
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "Telephony country diagnostic hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "TelephonyManager unavailable; region diagnostics skipped");
            return false;
        }
        regionDiagnosticsInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "read-only region compatibility diagnostics installed=" + installed + " for " + pkg);
        return regionDiagnosticsInstalled;
    }

"""
once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n",method+"    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")
path.write_text(source)
expected="6dd32af956e427f8f0b3f012f7e2631fef7860e2a7de230328d583864d99ad28"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=expected: raise SystemExit(f"region diagnostic source hash mismatch: {actual}")
print("API101 read-only region diagnostic patch: PASS",actual)
