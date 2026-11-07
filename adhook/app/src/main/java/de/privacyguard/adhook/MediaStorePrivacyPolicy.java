package de.privacyguard.adhook;

/** Fail-open policy for opt-in MediaStore/Media Documents query suppression. */
public final class MediaStorePrivacyPolicy {
    private MediaStorePrivacyPolicy() {}

    public static boolean shouldBlockMediaStore(boolean privacyEnabled, int processPackageCount,
                                                String packageName, UnifiedHookConfigParser.Target target,
                                                String scheme, String authority) {
        if (!privacyEnabled || processPackageCount != 1 || packageName == null || target == null) return false;
        if ("android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName)) return false;
        if (!target.blockMediaStore || !"content".equalsIgnoreCase(scheme) || authority == null) return false;
        return "media".equalsIgnoreCase(authority)
                || "com.android.providers.media.documents".equalsIgnoreCase(authority)
                || "com.android.providers.media.photopicker".equalsIgnoreCase(authority)
                || authority.toLowerCase(java.util.Locale.ROOT).endsWith(".media.documents");
    }
}
