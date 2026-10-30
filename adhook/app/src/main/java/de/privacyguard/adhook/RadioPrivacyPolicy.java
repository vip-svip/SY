package de.privacyguard.adhook;

/** Fail-open policies for radio-derived location metadata. */
public final class RadioPrivacyPolicy {
    private RadioPrivacyPolicy() {}

    public static boolean shouldHideWifiScan(boolean privacyEnabled, int processPackageCount,
                                             String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null
                && target != null && target.wifiScanHide;
    }

    public static boolean shouldHideCellInfo(boolean privacyEnabled, int processPackageCount,
                                             String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null
                && target != null && target.cellInfoHide;
    }
}
