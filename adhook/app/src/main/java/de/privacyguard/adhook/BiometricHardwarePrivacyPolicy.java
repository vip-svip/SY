package de.privacyguard.adhook;

/** Per-target fail-open policy for biometric hardware capability metadata. */
public final class BiometricHardwarePrivacyPolicy {
    private BiometricHardwarePrivacyPolicy() {}

    private static boolean eligible(boolean privacyEnabled, int processPackageCount,
                                    String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && target != null
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }

    public static boolean shouldHideFingerprint(boolean privacyEnabled, int processPackageCount,
                                                String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target)
                && target.hideFingerprintHw;
    }

    public static boolean shouldHideFace(boolean privacyEnabled, int processPackageCount,
                                         String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target)
                && target.hideFaceHw;
    }
}
