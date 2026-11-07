package de.privacyguard.adhook;

/** Fail-open policy for per-app microphone hardware enumeration privacy. */
public final class MicrophoneHardwarePrivacyPolicy {
    private MicrophoneHardwarePrivacyPolicy() {}

    public static boolean shouldHideInputDevices(boolean privacyEnabled, int processPackageCount,
                                                 String packageName,
                                                 UnifiedHookConfigParser.Target target) {
        if (!privacyEnabled || processPackageCount != 1 || packageName == null || target == null) return false;
        if ("android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName)) return false;
        return target.micHwHide;
    }
}
