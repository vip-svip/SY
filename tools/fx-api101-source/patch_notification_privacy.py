#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base = "fb46869ec48b21592927d39b0ae06143bb53b6c3578f7a15b1eda06d60cfd45f"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base:
    raise SystemExit(f"unexpected API101 source before notification privacy patch: {actual}")

def once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("notification privacy patch anchor mismatch: " + old[:120])
    source = source.replace(old, new, 1)

once("    private boolean audioFingerprintHooksInstalled;\n",
     "    private boolean audioFingerprintHooksInstalled;\n"
     "    private boolean notificationHooksInstalled;\n"
     "    private boolean usageStatsHooksInstalled;\n"
     "    private boolean accessibilityHooksInstalled;\n")

once(
    "        final boolean audioFpForPackage = privacyEnabled && target.audioFpBlock;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage && !passiveLocationForPackage && !regionDiagForPackage\n"
    "                && !mediaStoreForPackage) return;\n",
    "        final boolean audioFpForPackage = privacyEnabled && target.audioFpBlock;\n"
    "        final boolean blockNotifListenForPackage = privacyEnabled && target.blockNotifListen;\n"
    "        final boolean hideNotifPermForPackage = privacyEnabled && target.hideNotifPerm;\n"
    "        final boolean usageStatsForPackage = privacyEnabled && target.usageStatsOff;\n"
    "        final boolean accessibilityForPackage = privacyEnabled && target.a11yHide;\n"
    "        final boolean passiveLocationForPackage = privacyEnabled && target.disablePassiveLocation;\n"
    "        final boolean regionDiagForPackage = target.regionDiag;\n"
    "        final boolean mediaStoreForPackage = privacyEnabled && target.blockMediaStore;\n"
    "        if (!adsForPackage && !privacyForPackage && !exifForPackage && !clipboardBlockForPackage\n"
    "                && !sensorForPackage && !wifiScanForPackage && !cellInfoForPackage && !cameraIdForPackage\n"
    "                && !micBlockForPackage && !micHwHideForPackage && !audioFpForPackage\n"
    "                && !blockNotifListenForPackage && !hideNotifPermForPackage && !usageStatsForPackage && !accessibilityForPackage\n"
    "                && !passiveLocationForPackage && !regionDiagForPackage && !mediaStoreForPackage) return;\n")

once("        if (audioFpForPackage && !micBlockForPackage) installAudioFingerprintPrivacyHooks(pkg);\n",
     "        if (audioFpForPackage && !micBlockForPackage) installAudioFingerprintPrivacyHooks(pkg);\n"
     "        if (blockNotifListenForPackage || hideNotifPermForPackage) installNotificationPrivacyHooks(pkg);\n"
     "        if (usageStatsForPackage) installUsageStatsPrivacyHooks(pkg);\n"
     "        if (accessibilityForPackage) installAccessibilityPrivacyHooks(pkg);\n")

method = """    private boolean shouldHideActiveNotifications() {
        String pkg = currentPackage;
        return NotificationPrivacyPolicy.shouldHideActiveNotifications(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private boolean shouldHideNotificationPermission() {
        String pkg = currentPackage;
        return NotificationPrivacyPolicy.shouldHideNotificationPermission(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private boolean shouldHideUsageStats() {
        String pkg = currentPackage;
        return SystemSurfacePrivacyPolicy.shouldHideUsageStats(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private boolean shouldHideAccessibilityServices() {
        String pkg = currentPackage;
        return SystemSurfacePrivacyPolicy.shouldHideAccessibilityServices(
                privacyEnabled, processPackages.size(), pkg, targets.get(pkg)) && !NEVER.contains(pkg);
    }

    private static Object emptyCollectionResult(Method method) {
        Class<?> resultType = method.getReturnType();
        if (resultType.isArray())
            return java.lang.reflect.Array.newInstance(resultType.getComponentType(), 0);
        if (java.util.Set.class.isAssignableFrom(resultType)) return java.util.Collections.emptySet();
        if (java.util.Collection.class.isAssignableFrom(resultType)) return java.util.Collections.emptyList();
        return null;
    }

    private synchronized boolean installNotificationPrivacyHooks(final String pkg) {
        if (notificationHooksInstalled) return true;
        int installed = 0;
        for (String className : new String[]{
                "android.app.NotificationManager",
                "android.service.notification.NotificationListenerService"}) {
            try {
                Class<?> type = Class.forName(className, false, null);
                for (Method method : type.getDeclaredMethods()) {
                    if (!"getActiveNotifications".equals(method.getName())) continue;
                    try {
                        hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                                .intercept(chain -> {
                                    if (!shouldHideActiveNotifications()) return chain.proceed();
                                    Object empty = emptyCollectionResult(method);
                                    return empty != null ? empty : chain.proceed();
                                });
                        installed++;
                    } catch (Throwable ignored) {
                        logFx(Log.DEBUG, "notification history API unavailable");
                    }
                }
            } catch (Throwable ignored) {
                logFx(Log.DEBUG, "notification class unavailable: " + className);
            }
        }
        try {
            Class<?> type = Class.forName("android.app.NotificationManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"areNotificationsEnabled".equals(method.getName())
                        || method.getReturnType() != boolean.class) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideNotificationPermission() ? false : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {
            logFx(Log.DEBUG, "notification permission query API unavailable");
        }
        notificationHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in notification privacy hooks installed=" + installed + " for " + pkg);
        return notificationHooksInstalled;
    }

    private synchronized boolean installUsageStatsPrivacyHooks(final String pkg) {
        if (usageStatsHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.app.usage.UsageStatsManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                if (!"queryUsageStats".equals(method.getName())
                        || !java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideUsageStats()
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {
            logFx(Log.DEBUG, "UsageStatsManager query API unavailable");
        }
        usageStatsHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in usage-stats privacy hooks installed=" + installed + " for " + pkg);
        return usageStatsHooksInstalled;
    }

    private synchronized boolean installAccessibilityPrivacyHooks(final String pkg) {
        if (accessibilityHooksInstalled) return true;
        int installed = 0;
        try {
            Class<?> type = Class.forName("android.view.accessibility.AccessibilityManager", false, null);
            for (Method method : type.getDeclaredMethods()) {
                String name = method.getName();
                if (!"getEnabledAccessibilityServiceList".equals(name)
                        && !"getInstalledAccessibilityServiceList".equals(name)) continue;
                if (!java.util.List.class.isAssignableFrom(method.getReturnType())) continue;
                hook(method).setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                        .intercept(chain -> shouldHideAccessibilityServices()
                                ? java.util.Collections.emptyList() : chain.proceed());
                installed++;
            }
        } catch (Throwable ignored) {
            logFx(Log.DEBUG, "AccessibilityManager enumeration API unavailable");
        }
        accessibilityHooksInstalled = installed > 0;
        logFx(installed > 0 ? Log.INFO : Log.WARN,
                "opt-in accessibility privacy hooks installed=" + installed + " for " + pkg);
        return accessibilityHooksInstalled;
    }

"""
once("    /** Apply bounded low-amplitude noise to selected app capture buffers after a successful read. */\n",
     method + "    /** Apply bounded low-amplitude noise to selected app capture buffers after a successful read. */\n")

path.write_text(source)
actual = hashlib.sha256(path.read_bytes()).hexdigest()
print("API101 notification/system-surface privacy patch: PASS", actual)
