#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base_hash = "b3fa4c33d1efebad7681cf7afc7433073c036e41ea71f6d97ff0ad0aa8b92b86"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base_hash:
    raise SystemExit(f"unexpected rewarded-safe API101 source: {actual}")

def replace_once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("expected exactly one radio privacy patch anchor: " + old[:100])
    source = source.replace(old, new, 1)

replace_once(
    "    private volatile boolean clipboardReadHooksInstalled;\n    private volatile boolean sensorHooksInstalled;\n",
    "    private volatile boolean clipboardReadHooksInstalled;\n    private volatile boolean sensorHooksInstalled;\n"
    "    private boolean wifiScanHooksInstalled;\n"
    "    private boolean cellInfoHooksInstalled;\n"
)
replace_once(
    "        final boolean sensorForPackage = privacyEnabled && (target.sensorAccel || target.sensorGyro\n"
    "                || target.sensorLight || target.sensorMagnet || target.sensorPressure || target.sensorProx\n"
    "                || target.sensorRateLimit);\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage && !sensorForPackage) return;\n",
    "        final boolean sensorForPackage = privacyEnabled && (target.sensorAccel || target.sensorGyro\n"
    "                || target.sensorLight || target.sensorMagnet || target.sensorPressure || target.sensorProx\n"
    "                || target.sensorRateLimit);\n"
    "        final boolean wifiScanForPackage = privacyEnabled && target.wifiScanHide;\n"
    "        final boolean cellInfoForPackage = privacyEnabled && target.cellInfoHide;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage) return;\n"
)
replace_once(
    "        if (clipboardBlockForPackage) installClipboardReadBlockHooks(pkg);\n"
    "        if (sensorForPackage) installSensorEnumerationHooks(pkg);\n",
    "        if (clipboardBlockForPackage) installClipboardReadBlockHooks(pkg);\n"
    "        if (sensorForPackage) installSensorEnumerationHooks(pkg);\n"
    "        if (wifiScanForPackage) installWifiScanPrivacyHooks(pkg);\n"
    "        if (cellInfoForPackage) installCellInfoPrivacyHooks(pkg);\n"
)
replace_once(
    "                \" overlay=\" + target.overlay + \" memberDiagReadOnly=\" + target.memberDiag +\n"
    "                \" sdk=\" + Build.VERSION.SDK_INT);\n",
    "                \" overlay=\" + target.overlay + \" memberDiagReadOnly=\" + target.memberDiag +\n"
    "                \" wifiScanHide=\" + wifiScanForPackage + \" cellInfoHide=\" + cellInfoForPackage +\n"
    "                \" sdk=\" + Build.VERSION.SDK_INT);\n"
)
methods = """    /** Hide Wi-Fi scan-result data for a single opted-in app; shared processes fail open. */
    private synchronized boolean installWifiScanPrivacyHooks(final String pkg) {
        if (wifiScanHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.net.wifi.WifiManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"getScanResults".equals(method.getName()) || method.getParameterTypes().length != 0
                        || !java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (!NEVER.contains(activePackage) && RadioPrivacyPolicy.shouldHideWifiScan(
                                        privacyEnabled, processPackages.size(), activePackage, active)) {
                                    return Collections.emptyList();
                                }
                                return chain.proceed();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "Wi-Fi scan result hook unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "WifiManager unavailable; Wi-Fi scan privacy fails open");
            return false;
        }
        wifiScanHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in Wi-Fi scan result redaction installed=" + installed + " for " + pkg);
        return wifiScanHooksInstalled;
    }

    /** Redact cell-location and cell-info results without altering SIM/network identity APIs. */
    private synchronized boolean installCellInfoPrivacyHooks(final String pkg) {
        if (cellInfoHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.telephony.TelephonyManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                String name = method.getName();
                Class<?>[] parameters = method.getParameterTypes();
                if (parameters.length != 0) continue;
                boolean listResult = ("getAllCellInfo".equals(name) || "getNeighboringCellInfo".equals(name))
                        && java.util.List.class.isAssignableFrom(method.getReturnType());
                boolean locationResult = "getCellLocation".equals(name)
                        && !method.getReturnType().isPrimitive();
                if (!listResult && !locationResult) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                if (!NEVER.contains(activePackage) && RadioPrivacyPolicy.shouldHideCellInfo(
                                        privacyEnabled, processPackages.size(), activePackage, active)) {
                                    return listResult ? Collections.emptyList() : null;
                                }
                                return chain.proceed();
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "cell-info hook unavailable: " + name);
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "TelephonyManager unavailable; cell-info privacy fails open");
            return false;
        }
        cellInfoHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in cell-info redaction installed=" + installed + " for " + pkg);
        return cellInfoHooksInstalled;
    }

"""
replace_once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n", methods + "    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")
path.write_text(source)
expected = "0d8d93d911d89e9a084f6160511cfc2dac40915652091fc9ac36ffeec3625c48"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"radio privacy source hash mismatch: {actual}")
print("API101 Wi-Fi scan/cell-info privacy patch: PASS", actual)
