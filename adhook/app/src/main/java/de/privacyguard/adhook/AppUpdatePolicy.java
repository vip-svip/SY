package de.privacyguard.adhook;

/**
 * Per-target gate for suppressing in-app "new version available" flows.
 *
 * Two independent capabilities:
 *
 *  - {@link #shouldReportUpToDate}: version checks report "already current", so the
 *    app does not prompt, force-update or nag.
 *  - {@link #resolveReportedVersion}: a chosen version string is reported instead of
 *    the installed one, which is what an app compares against its update manifest.
 *
 * Both are opt-in per target and fail closed: the privacy master must be on, this
 * process must be a single configured target, platform/manager/store packages are
 * never eligible, and a version override is only used when it is a plausible version
 * string. Nothing here modifies the installed package, its signature or Play/OTA state.
 */
public final class AppUpdatePolicy {
    private AppUpdatePolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager", "com.android.vending"
    };

    /** Version strings are bounded and restricted to a plausible version literal. */
    private static final int MAX_VERSION_LENGTH = 32;

    /**
     * Report the "no update" state for this package.
     */
    public static boolean shouldReportUpToDate(boolean privacyMasterEnabled,
                                               int processPackageCount,
                                               String packageName,
                                               UnifiedHookConfigParser.Target target) {
        if (!eligible(privacyMasterEnabled, processPackageCount, packageName, target)) return false;
        return target.blockAppUpdate;
    }

    /**
     * The version string to report instead of the installed one, or null to leave it.
     */
    public static String resolveReportedVersion(boolean privacyMasterEnabled,
                                                int processPackageCount,
                                                String packageName,
                                                UnifiedHookConfigParser.Target target) {
        if (!eligible(privacyMasterEnabled, processPackageCount, packageName, target)) return null;
        if (!target.fakeAppVersion) return null;
        String configured = target.simulatedAppVersion;
        if (configured == null) return null;
        String trimmed = configured.trim();
        if (!isPlausibleVersion(trimmed)) return null;
        return trimmed;
    }

    /**
     * A version override must look like a version: digits with at most three dots, an
     * optional leading 'v', and an optional alphanumeric suffix. This keeps an
     * accidental empty or free-text value from being reported to the app.
     */
    public static boolean isPlausibleVersion(String value) {
        if (value == null || value.isEmpty() || value.length() > MAX_VERSION_LENGTH) return false;
        String candidate = value;
        if (candidate.length() > 1 && (candidate.charAt(0) == 'v' || candidate.charAt(0) == 'V')) {
            candidate = candidate.substring(1);
        }
        int dots = 0;
        int digits = 0;
        for (int i = 0; i < candidate.length(); i++) {
            char c = candidate.charAt(i);
            if (c >= '0' && c <= '9') {
                digits++;
            } else if (c == '.') {
                if (digits == 0) return false;
                if (++dots > 3) return false;
                digits = 0;
            } else if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_') {
                // Suffix marker (e.g. 1.2.3-beta): the numeric part must be complete.
                return digits > 0 && i > 0 && noDotTerminator(candidate, i);
            } else {
                return false;
            }
        }
        return digits > 0;
    }

    private static boolean noDotTerminator(String value, int from) {
        return from > 0 && value.charAt(from - 1) != '.';
    }

    private static boolean eligible(boolean privacyMasterEnabled, int processPackageCount,
                                    String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        return target != null;
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
