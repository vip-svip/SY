package de.privacyguard.adhook;

/** Fail-open policies for radio-derived location metadata. */
public final class RadioPrivacyPolicy {
    private RadioPrivacyPolicy() {}

    private static boolean protectedPackage(String packageName) {
        return "android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName);
    }

    public static boolean shouldHideWifiScan(boolean privacyEnabled, int processPackageCount,
                                             String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null
                && !protectedPackage(packageName) && target != null && target.wifiScanHide;
    }

    public static boolean shouldHideCellInfo(boolean privacyEnabled, int processPackageCount,
                                             String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null
                && !protectedPackage(packageName) && target != null && target.cellInfoHide;
    }
}
