package de.privacyguard.adhook;

/** Fail-open policy for usage-statistics and accessibility-service enumeration. */
public final class SystemSurfacePrivacyPolicy {
    private SystemSurfacePrivacyPolicy() {}

    private static boolean eligible(boolean privacyEnabled, int processPackageCount,
                                    String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null && target != null
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }

    public static boolean shouldHideUsageStats(boolean privacyEnabled, int processPackageCount,
                                               String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target) && target.usageStatsOff;
    }

    public static boolean shouldHideAccessibilityServices(boolean privacyEnabled, int processPackageCount,
                                                           String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target) && target.a11yHide;
    }
}
