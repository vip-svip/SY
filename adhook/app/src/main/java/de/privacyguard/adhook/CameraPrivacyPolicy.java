package de.privacyguard.adhook;

/** Fail-open policy for camera hardware enumeration. */
public final class CameraPrivacyPolicy {
    private CameraPrivacyPolicy() {}

    public static boolean shouldHideCameraIds(boolean privacyEnabled, int processPackageCount,
                                              String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyEnabled || processPackageCount != 1 || packageName == null || target == null) return false;
        if ("android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName)) return false;
        return target.cameraIdHide;
    }
}
