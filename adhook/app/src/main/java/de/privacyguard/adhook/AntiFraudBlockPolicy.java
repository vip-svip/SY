package de.privacyguard.adhook;

/**
 * Gate for blocking state anti-fraud ("国家反诈") collection.
 *
 * Two surfaces are covered:
 *
 *  - in-app SDKs: 反诈 SDKs commonly read the installed-app inventory, the contact
 *    book, the SMS inbox, the call log, the clipboard and the device identifiers to
 *    build a risk profile. Their reads are redirected to empty results.
 *  - system-side collectors: the OEM/framework anti-fraud components enumerate the
 *    same data through the same public APIs, so the same redirect applies when the
 *    package is a known anti-fraud component.
 *
 * The gate is per-target, opt-in and fail-closed, and it never touches FX itself,
 * the platform, or the module manager.
 */
public final class AntiFraudBlockPolicy {
    private AntiFraudBlockPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager"
    };

    /**
     * Package-name markers for anti-fraud components. These are matched against the
     * process package only, never against a class name, so an unrelated app that
     * merely mentions the word is unaffected.
     */
    private static final String[] ANTIFRAUD_MARKERS = {
            "antifraud", "anti_fraud", "fanfraud", "fan_zha", "fanzha",
            "96110", "nationalanti", "gjfz", "gongan", "police"
    };

    /** Data sources the anti-fraud SDKs read; each maps to a real hook surface. */
    public enum Surface {
        INSTALLED_APPS,
        CONTACTS,
        SMS,
        CALL_LOG,
        CLIPBOARD,
        DEVICE_IDENTIFIER,
        LOCATION
    }

    public static boolean shouldBlock(boolean privacyMasterEnabled, int processPackageCount,
                                      String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        return target != null && target.antiFraudBlock;
    }

    /**
     * Whether this package itself is an anti-fraud component. Used to keep the
     * system-side collector blocked even when the user only enabled the in-app switch
     * for another target.
     */
    public static boolean isAntiFraudComponent(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        String normalized = packageName.toLowerCase(java.util.Locale.ROOT);
        for (String marker : ANTIFRAUD_MARKERS) {
            if (normalized.contains(marker)) return true;
        }
        return false;
    }

    /** Per-surface gate so a single switch can be traced to the hook it drives. */
    public static boolean shouldBlockSurface(boolean privacyMasterEnabled,
                                             int processPackageCount,
                                             String packageName,
                                             UnifiedHookConfigParser.Target target,
                                             Surface surface) {
        if (surface == null) return false;
        if (!shouldBlock(privacyMasterEnabled, processPackageCount, packageName, target)) {
            return false;
        }
        // Location is only blocked when the target did not ask for a simulated fix;
        // otherwise injection and blocking would contradict each other.
        if (surface == Surface.LOCATION && target != null && target.locationSimulation) {
            return false;
        }
        return true;
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
