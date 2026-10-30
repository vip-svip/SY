#!/usr/bin/env python3
from pathlib import Path
import hashlib
path=Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source=path.read_text()
base="6dd32af956e427f8f0b3f012f7e2631fef7860e2a7de230328d583864d99ad28"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=base: raise SystemExit(f"unexpected region-diagnostic source: {actual}")
def once(old,new):
 global source
 if source.count(old)!=1: raise SystemExit("MediaStore patch anchor mismatch: "+old[:100])
 source=source.replace(old,new,1)
once("    private boolean regionDiagnosticsInstalled;\n","    private boolean regionDiagnosticsInstalled;\n    private boolean mediaStoreHooksInstalled;\n")
once(
"        final boolean regionDiagForPackage = target.regionDiag;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage && !passiveLocationForPackage && !regionDiagForPackage) return;\n",
"        final boolean regionDiagForPackage = target.regionDiag;\n"
"        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
"        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
"                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
"                && !micBlockForPackage && !passiveLocationForPackage && !regionDiagForPackage\n"
"                && !mediaStoreForPackage) return;\n")
once("        if (regionDiagForPackage) installRegionCompatibilityDiagnostics(pkg);\n",
     "        if (regionDiagForPackage) installRegionCompatibilityDiagnostics(pkg);\n        if (mediaStoreForPackage) installMediaStorePrivacyHooks(pkg);\n")
once(
"                + \" passiveLocationHide=\" + passiveLocationForPackage + \" regionDiag=\" + regionDiagForPackage\n"
"                + \" sdk=\" + Build.VERSION.SDK_INT);\n",
"                + \" passiveLocationHide=\" + passiveLocationForPackage + \" regionDiag=\" + regionDiagForPackage\n"
"                + \" mediaStoreBlock=\" + mediaStoreForPackage + \" sdk=\" + Build.VERSION.SDK_INT);\n")
method="""    /** Return empty cursors for selected MediaStore queries; direct files and SAF are not covered. */
    private synchronized boolean installMediaStorePrivacyHooks(final String pkg) {
        if (mediaStoreHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.content.ContentResolver", false, null);
            Class<?> uriType = Class.forName("android.net.Uri", false, null);
            Class<?> cursorType = Class.forName("android.database.Cursor", false, null);
            for (Method method : type.getDeclaredMethods()) {
                Class<?>[] parameters = method.getParameterTypes();
                if (!"query".equals(method.getName()) || parameters.length < 1
                        || parameters[0] != uriType || !cursorType.isAssignableFrom(method.getReturnType())) continue;
                try {
                    hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                            .intercept(chain -> {
                                String activePackage = currentPackage;
                                UnifiedHookConfigParser.Target active = targets.get(activePackage);
                                java.util.List<Object> args = chain.getArgs();
                                Object uriObject = args.isEmpty() ? null : args.get(0);
                                if (!(uriObject instanceof android.net.Uri)) return chain.proceed();
                                android.net.Uri uri = (android.net.Uri) uriObject;
                                if (!MediaStorePrivacyPolicy.shouldBlockMediaStore(privacyEnabled,
                                        processPackages.size(), activePackage, active,
                                        uri.getScheme(), uri.getAuthority()) || NEVER.contains(activePackage)) {
                                    return chain.proceed();
                                }
                                android.database.Cursor original = (android.database.Cursor) chain.proceed();
                                if (original == null) return null;
                                try {
                                    android.database.MatrixCursor empty =
                                            new android.database.MatrixCursor(original.getColumnNames());
                                    try { original.close(); } catch (Throwable ignored) { }
                                    return empty;
                                } catch (Throwable t) {
                                    logFx(Log.WARN, "MediaStore empty-cursor creation failed; query fails open");
                                    return original;
                                }
                            });
                    installed++;
                } catch (Throwable t) {
                    logFx(Log.DEBUG, "ContentResolver query overload unavailable");
                }
            }
        } catch (Throwable t) {
            logFx(Log.WARN, "ContentResolver unavailable; MediaStore privacy fails open");
            return false;
        }
        mediaStoreHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in MediaStore query suppression installed=" + installed + " for " + pkg);
        return mediaStoreHooksInstalled;
    }

"""
once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n",method+"    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")
path.write_text(source)
expected="ebaec0c3089990a3c2994518abda42cd4f57bf5c5e6f6957e67c0ec4d63d5e1a"
actual=hashlib.sha256(path.read_bytes()).hexdigest()
if actual!=expected: raise SystemExit(f"MediaStore source hash mismatch: {actual}")
print("API101 MediaStore privacy patch: PASS",actual)
