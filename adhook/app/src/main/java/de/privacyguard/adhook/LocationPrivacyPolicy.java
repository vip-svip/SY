package de.privacyguard.adhook;

/** Fail-open policy for hiding cached passive location results. */
public final class LocationPrivacyPolicy {
    private LocationPrivacyPolicy() {}

    public static boolean shouldHideLastKnownLocation(boolean privacyEnabled, int processPackageCount,
                                                      String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyEnabled || processPackageCount != 1 || packageName == null || target == null) return false;
        if ("android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName)) return false;
        return target.disablePassiveLocation;
    }
}
