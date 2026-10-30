package de.privacyguard.adhook;

/** Fail-open, per-package policy for notification API privacy. */
public final class NotificationPrivacyPolicy {
    private NotificationPrivacyPolicy() {}

    private static boolean eligible(boolean privacyEnabled, int processPackageCount,
                                    String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null && target != null
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }

    public static boolean shouldHideActiveNotifications(boolean privacyEnabled, int processPackageCount,
                                                        String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target) && target.blockNotifListen;
    }

    public static boolean shouldHideNotificationPermission(boolean privacyEnabled, int processPackageCount,
                                                           String packageName, UnifiedHookConfigParser.Target target) {
        return eligible(privacyEnabled, processPackageCount, packageName, target) && target.hideNotifPerm;
    }
}
