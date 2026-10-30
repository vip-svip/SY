#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "abe61fe86118a3f0586dde534a7a638b596c61ba9cf7530479c8c79416f87bb4"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before Advertising ID patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("Advertising ID patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private volatile boolean privacyIdentifierHookInstalled;\n",
     "    private volatile boolean privacyIdentifierHookInstalled;\n"
     "    private volatile boolean googleAdvertisingIdHooksInstalled;\n"
     "    private volatile boolean huaweiAdvertisingIdHooksInstalled;\n")

once("        final boolean privacyForPackage = privacyEnabled && target.privacy;\n",
     "        final boolean privacyForPackage = privacyEnabled && target.privacy;\n"
     "        final boolean adIdUnifyForPackage = privacyEnabled && target.adIdUnify;\n")

once("        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n",
     "        if (!adsForPackage && !privacyForPackage && !adIdUnifyForPackage && !exifForPackage && !clipboardBlockForPackage\n")

once("        if (privacyForPackage) installPrivacyIdentifierHooks(pkg);\n",
     "        if (privacyForPackage) installPrivacyIdentifierHooks(pkg);\n"
     "        if (adIdUnifyForPackage) installAdvertisingIdPrivacyHooks(pkg, param.getClassLoader());\n")

method = """    private boolean shouldUnifyAdvertisingId() {
        String pkg = currentPackage;
        return AdvertisingIdPrivacyPolicy.shouldUnify(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private String syntheticAdvertisingId() {
        if (!shouldUnifyAdvertisingId()) return null;
        return AdvertisingIdPrivacyPolicy.syntheticId(currentPackage);
    }

    /**
     * Isolate Google Mobile Services and Huawei Advertising IDs per selected app.
     * This is local identifier privacy only; it does not alter account, purchase,
     * reward, server entitlement or billing state. Unknown SDK APIs fail open.
     */
    private synchronized boolean installAdvertisingIdPrivacyHooks(final String pkg, ClassLoader appClassLoader) {
        int installed = 0;
        if (!googleAdvertisingIdHooksInstalled) {
            try {
                Class<?> info = Class.forName(
                        "com.google.android.gms.ads.identifier.AdvertisingIdClient$Info", false, appClassLoader);
                for (Method method : info.getDeclaredMethods()) {
                    if (!"getId".equals(method.getName()) || method.getParameterTypes().length != 0
                            || method.getReturnType() != String.class) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    String replacement = syntheticAdvertisingId();
                                    return replacement == null ? chain.proceed() : replacement;
                                });
                        installed++;
                    } catch (Throwable ignored) {
                        logFx(Log.DEBUG, "Google Advertising ID method unavailable");
                    }
                }
                googleAdvertisingIdHooksInstalled = installed > 0;
            } catch (Throwable ignored) {
                logFx(Log.DEBUG, "Google Advertising ID SDK unavailable; fail open");
            }
        }
        if (!huaweiAdvertisingIdHooksInstalled) {
            int huaweiInstalled = 0;
            for (String className : new String[]{
                    "com.huawei.hms.ads.identifier.AdvertisingIdClient",
                    "com.huawei.hms.ads.identifier.AdvertisingIdClient$Info"}) {
                try {
                    Class<?> type = Class.forName(className, false, appClassLoader);
                    for (Method method : type.getDeclaredMethods()) {
                        String name = method.getName();
                        boolean candidate = "getId".equals(name) || "getAdvertisingId".equals(name)
                                || "getOaid".equals(name);
                        if (!candidate || method.getReturnType() != String.class) continue;
                        try {
                            hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                    .intercept(chain -> {
                                        String replacement = syntheticAdvertisingId();
                                        return replacement == null ? chain.proceed() : replacement;
                                    });
                            huaweiInstalled++;
                        } catch (Throwable ignored) {
                            logFx(Log.DEBUG, "Huawei Advertising ID method unavailable");
                        }
                    }
                } catch (Throwable ignored) {
                    // Huawei SDK is optional; continue checking the alternate class.
                }
            }
            huaweiAdvertisingIdHooksInstalled = huaweiInstalled > 0;
            installed += huaweiInstalled;
        }
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in app-scoped Advertising ID hooks installed=" + installed + " for " + pkg);
        return googleAdvertisingIdHooksInstalled || huaweiAdvertisingIdHooksInstalled;
    }

"""
once("    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n",
     method + "    private synchronized boolean installPrivacyIdentifierHooks(final String pkg) {\n")

path.write_text(source)
expected = "c97f6272fcbf667fd8c3b419f607204e44dbe1b5ea034cf0ab87468745129b42"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"Advertising ID source hash mismatch: {actual}")
print("API101 Advertising ID privacy patch: PASS", actual)
