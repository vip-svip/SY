package de.privacyguard.adhook;

/** Per-app fail-open gate for biometric hardware concealment. */
public final class BiometricPrivacyPolicy {
    private BiometricPrivacyPolicy() {}

    private static boolean eligible(boolean privacyEnabled, int processPackageCount,
                                    String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null && target != null
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }

    public static boolean shouldHideFingerprint(boolean privacyEnabled, int processPackageCount,
                                                String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target) && target.hideFingerprintHw;
    }

    public static boolean shouldHideFace(boolean privacyEnabled, int processPackageCount,
                                         String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target) && target.hideFaceHw;
    }

    public static boolean shouldReportNoBiometricHardware(boolean privacyEnabled, int processPackageCount,
                                                          String packageName, UnifiedHookConfigParser.Target target) {
        return shouldHideFingerprint(privacyEnabled, processPackageCount, packageName, target)
                || shouldHideFace(privacyEnabled, processPackageCount, packageName, target);
    }
}
