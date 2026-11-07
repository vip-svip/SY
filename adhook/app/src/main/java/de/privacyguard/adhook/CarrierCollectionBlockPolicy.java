package de.privacyguard.adhook;

/**
 * Gate for blocking carrier-side collection.
 *
 * Carriers and their embedded SDKs collect identifiers and behaviour through public
 * platform APIs. Each surface below maps to a real hook in the runtime:
 *
 *  - SUBSCRIBER_ID / SIM_SERIAL / LINE_NUMBER  -> TelephonyManager identity getters
 *  - SUBSCRIBER_COUNT / SIM_OPERATOR            -> subscription enumeration
 *  - CELL_INFO / SIGNAL_STRENGTH                -> cell + signal metadata (locates the user)
 *  - DATA_USAGE                                 -> network statistics / per-UID traffic
 *  - IMSI_CARRIER_APP                           -> carrier-service package reads
 *
 * Per-target, opt-in, fail-closed; FX, the platform and the module manager never qualify.
 */
public final class CarrierCollectionBlockPolicy {
    private CarrierCollectionBlockPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager"
    };

    /** Package markers for carrier-service components. */
    private static final String[] CARRIER_MARKERS = {
            "chinamobile", "10086", "cmcc", "chinaunicom", "10010", "unicom",
            "chinatelecom", "10000", "telecom", "ctcc", "carrier", "simtoolkit",
            "uim", "csim"
    };

    public enum Surface {
        SUBSCRIBER_ID,
        SIM_SERIAL,
        LINE_NUMBER,
        SUBSCRIBER_COUNT,
        SIM_OPERATOR,
        CELL_INFO,
        SIGNAL_STRENGTH,
        DATA_USAGE,
        CARRIER_SERVICE_PACKAGE
    }

    public static boolean shouldBlock(boolean privacyMasterEnabled, int processPackageCount,
                                      String packageName, UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        return target != null && target.carrierCollectionBlock;
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
        // A target that hides only the radio metadata keeps identity reads intact,
        // so honour the narrower switch when it is the one the user chose.
        if (surface == Surface.CELL_INFO || surface == Surface.SIGNAL_STRENGTH) {
            return true;
        }
        return true;
    }

    /** Whether this package is a carrier-service component. */
    public static boolean isCarrierComponent(String packageName) {
        if (packageName == null || packageName.isEmpty()) return false;
        String normalized = packageName.toLowerCase(java.util.Locale.ROOT);
        for (String marker : CARRIER_MARKERS) {
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
