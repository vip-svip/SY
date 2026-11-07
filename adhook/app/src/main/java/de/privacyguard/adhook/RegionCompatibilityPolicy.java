package de.privacyguard.adhook;

/** Read-only local region compatibility diagnostics; never changes IP or account eligibility. */
public final class RegionCompatibilityPolicy {
    private RegionCompatibilityPolicy() {}

    public static boolean shouldObserveRegion(int processPackageCount, String packageName,
                                              UnifiedHookConfigParser.Target target) {
        if (processPackageCount != 1 || packageName == null || target == null) return false;
        if ("android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName)) return false;
        return target.regionDiag;
    }
}
