package de.privacyguard.adhook;

/** Per-package, opt-in sensor enumeration policy. Unknown sensor types fail open. */
public final class SensorPrivacyPolicy {
    private SensorPrivacyPolicy() {}
    public static boolean isEnabled(UnifiedHookConfigParser.Target target, int type) {
        if (target == null) return false;
        switch (type) {
            case 1: return target.sensorAccel;
            case 2: return target.sensorMagnet;
            case 4: return target.sensorGyro;
            case 5: return target.sensorLight;
            case 6: return target.sensorPressure;
            case 8: return target.sensorProx;
            default: return false;
        }
    }
    public static boolean shouldClampRate(boolean privacyMaster, int processPackageCount,
                                          String packageName, UnifiedHookConfigParser.Target target) {
        return privacyMaster && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && !isProtected(packageName)
                && target != null && target.sensorRateLimit;
    }

    /** Legacy behavior: clamp requested periods below 100 ms to 100 ms (at most 10 Hz). */
    public static int clampSamplingPeriodUs(int requestedPeriodUs) {
        return requestedPeriodUs < 100000 ? 100000 : requestedPeriodUs;
    }

    public static boolean shouldHide(boolean privacyMaster, int processPackageCount,
                                     String packageName, UnifiedHookConfigParser.Target target, int type) {
        return privacyMaster && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && !isProtected(packageName) && isEnabled(target, type);
    }
    private static boolean isProtected(String pkg) {
        return "android".equals(pkg) || "system".equals(pkg)
                || "de.privacyguard.hook".equals(pkg) || "de.privacyguard.adhook".equals(pkg)
                || "org.lsposed.manager".equals(pkg);
    }
}
