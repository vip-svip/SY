package de.privacyguard.adhook.imported.ad;

/** Fail-closed identity check for Root-backed Tasker broadcasts. */
public final class FxYulongTaskerCallerPolicy {
    public static final int MIN_VERIFIABLE_API = 34;

    private FxYulongTaskerCallerPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_-]+)+")
                && !value.contains("..")
                && !"de.privacyguard.adhook".equals(value);
    }

    /**
     * API 34 exposes the actual originating package/UID for a delivered broadcast.
     * Older Android releases cannot safely authenticate this exported Root receiver
     * using public BroadcastReceiver APIs, so they are deliberately rejected.
     */
    public static boolean isAuthorized(int sdkInt, String senderPackage, int senderUid,
                                       String configuredPackage, String[] packagesForUid) {
        if (sdkInt < MIN_VERIFIABLE_API || senderUid < 0
                || !isValidPackageName(configuredPackage)
                || !configuredPackage.equals(senderPackage)
                || packagesForUid == null || packagesForUid.length == 0) {
            return false;
        }
        for (String packageName : packagesForUid) {
            if (configuredPackage.equals(packageName)) return true;
        }
        return false;
    }
}
