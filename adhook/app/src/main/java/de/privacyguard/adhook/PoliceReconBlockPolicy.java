package de.privacyguard.adhook;

/**
 * Gate for blocking "网警"/public-security reconnaissance.
 *
 * Reconnaissance tooling and public-security inspection apps probe the device for
 * evidence about the user: installed package inventory, running processes, device
 * identifiers, network/VPN state, root artifacts and the accessibility-service list.
 * Blocking that reconnaissance means those enumeration reads return a neutral
 * baseline for the opted-in target instead of the real device state.
 *
 * Per-target, opt-in, fail-closed. FX, the platform and the module manager never
 * qualify, and the gate never hides the presence of FX itself from LSPosed.
 */
public final class PoliceReconBlockPolicy {
    private PoliceReconBlockPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager"
    };

    /** Package markers for inspection/recon components. */
    private static final String[] RECON_MARKERS = {
            "police", "jingcha", "jingwang", "gongan", "wangjing", "netpolice",
            "inspect", "forensic", "evidence", "取证", "checker", "detector",
            "devicecheck", "securitycheck", "riskcheck", "safetyscan"
    };

    public enum Surface {
        INSTALLED_PACKAGES,
        RUNNING_PROCESSES,
        DEVICE_IDENTIFIER,
        NETWORK_STATE,
        VPN_STATE,
        ROOT_ARTIFACT,
        ACCESSIBILITY_SERVICES,
        SCREENSHOT_GUARD
    }

    public static boolean shouldBlock(boolean privacyMasterEnabled, int processPackageCount,
                                      String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        return target != null && target.policeReconBlock;
    }

    public static boolean shouldBlockSurface(boolean privacyMasterEnabled,
                                             int processPackageCount,
                                             String packageName,
                                             UnifiedHookConfigParser.Target target,
                                             Surface surface) {
        if (surface == null) return false;
        if (!shouldBlock(privacyMasterEnabled, processPackageCount, packageName, target)) {
            return false;
        }
        // A target that asked to hide VPN detection already owns that surface; the
        // recon switch must not create a second, competing answer.
        if (surface == Surface.VPN_STATE && target != null && target.vpnDetectionHidden) {
            return false;
        }
        return true;
    }

    /** Whether this package looks like an inspection/recon component. */
    public static boolean isReconComponent(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        String normalized = packageName.toLowerCase(java.util.Locale.ROOT);
        for (String marker : RECON_MARKERS) {
            if (normalized.contains(marker)) return true;
        }
        return false;
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
