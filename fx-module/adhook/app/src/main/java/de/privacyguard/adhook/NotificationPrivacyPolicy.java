package de.privacyguard.adhook;

/** Fail-open policy for per-app active-notification read suppression. */
public final class NotificationPrivacyPolicy {
    private NotificationPrivacyPolicy() {}
    public static boolean shouldBlock(boolean masterEnabled, int processPackageCount, String packageName, UnifiedHookConfigParser.Target target) {
        return masterEnabled && processPackageCount == 1 && packageName != null && !packageName.isEmpty()
                && !isProtected(packageName) && target != null && target.notificationListenBlock;
    }
    /** Hide the app-visible notification-enabled query only; never revoke or mutate permission state. */
    public static boolean shouldHidePermission(boolean masterEnabled, int processPackageCount,
                                               String packageName, UnifiedHookConfigParser.Target target) {
        return masterEnabled && processPackageCount == 1 && packageName != null
                && !packageName.isEmpty() && !isProtected(packageName)
                && target != null && target.notificationPermissionHide;
    }

    private static boolean isProtected(String pkg) {
        return "android".equals(pkg) || "system".equals(pkg) || "de.privacyguard.hook".equals(pkg)
                || "de.privacyguard.adhook".equals(pkg) || "org.lsposed.manager".equals(pkg);
    }
}
