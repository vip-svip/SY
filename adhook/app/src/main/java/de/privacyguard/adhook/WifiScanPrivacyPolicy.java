package de.privacyguard.adhook;

/** Pure fail-open policy for per-package Wi-Fi scan privacy. */
public final class WifiScanPrivacyPolicy {
    private WifiScanPrivacyPolicy() {}

    public static boolean shouldBlock(boolean masterEnabled, int processPackageCount,
                                      String packageName, UnifiedHookConfigParser.Target target) {
        return masterEnabled && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && !isProtected(packageName)
                && target != null && target.wifiScanBlock;
    }

    private static boolean isProtected(String pkg) {
        return "android".equals(pkg) || "system".equals(pkg)
                || "de.privacyguard.hook".equals(pkg) || "de.privacyguard.adhook".equals(pkg)
                || "org.lsposed.manager".equals(pkg);
    }
}
