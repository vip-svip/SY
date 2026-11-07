package de.privacyguard.adhook;

/**
 * Per-target gate for generic VIP / paid-entitlement reporting.
 *
 * This policy decides only whether FX may *report* a simulated entitlement state to
 * the hooked app. It is deliberately fail-closed:
 *
 *  - the privacy master must be on;
 *  - the process must be a single, explicitly configured target package;
 *  - the target must have opted in explicitly;
 *  - platform / manager packages are never eligible.
 *
 * The simulated state is presentation data for the app's own membership UI. Nothing
 * here touches purchase receipts, billing callbacks or server-side verification, and
 * the gate never widens the app's real capability surface.
 */
public final class VipEntitlementPolicy {
    private VipEntitlementPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager", "com.android.vending"
    };

    /**
     * @param privacyMasterEnabled the global privacy switch
     * @param processPackageCount how many packages share this process (1 = dedicated)
     * @param packageName the process package
     * @param target the parsed per-app target, or null
     */
    public static boolean shouldExposeSimulatedEntitlement(boolean privacyMasterEnabled,
                                                           int processPackageCount,
                                                           String packageName,
                                                           UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        if (target == null || !target.vipEntitlementSimulation) return false;
        // A defined simulated state is mandatory: exposing "simulated" without a value
        // would report an undefined entitlement instead of a chosen test state.
        return target.simulatedEntitlementState != null
                && !target.simulatedEntitlementState.isEmpty();
    }

    /** The state to report, or null when the gate is closed. */
    public static String resolveReportedState(boolean privacyMasterEnabled,
                                              int processPackageCount,
                                              String packageName,
                                              UnifiedHookConfigParser.Target target) {
        return shouldExposeSimulatedEntitlement(privacyMasterEnabled, processPackageCount,
                packageName, target) ? target.simulatedEntitlementState : null;
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
