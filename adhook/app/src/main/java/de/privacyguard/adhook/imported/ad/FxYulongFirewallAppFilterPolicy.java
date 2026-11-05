package de.privacyguard.adhook.imported.ad;

/** Pure package classification for the Yulong per-app firewall list. */
public final class FxYulongFirewallAppFilterPolicy {
    public static final int ALL_APPS = 0;
    public static final int USER_APPS = 1;
    public static final int SYSTEM_APPS = 2;

    // Android ApplicationInfo.FLAG_SYSTEM and FLAG_UPDATED_SYSTEM_APP.
    // Keep this policy class Android-free so its classification is host-testable.
    private static final int FLAG_SYSTEM = 1;
    private static final int FLAG_UPDATED_SYSTEM_APP = 128;

    private FxYulongFirewallAppFilterPolicy() { }

    public static boolean includes(int mode, int applicationFlags) {
        boolean systemApp = (applicationFlags & FLAG_SYSTEM) != 0
                || (applicationFlags & FLAG_UPDATED_SYSTEM_APP) != 0;
        switch (mode) {
            case ALL_APPS:
                return true;
            case USER_APPS:
                return !systemApp;
            case SYSTEM_APPS:
                return systemApp;
            default:
                return false;
        }
    }
}
