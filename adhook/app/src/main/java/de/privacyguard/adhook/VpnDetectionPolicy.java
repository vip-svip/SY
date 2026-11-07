package de.privacyguard.adhook;

/**
 * Per-target gate for VPN-detection suppression.
 *
 * Hooked apps routinely ask the platform "is there a VPN up?" via NetworkCapabilities,
 * ConnectivityManager, NetworkInfo and the legacy interface list. This policy decides
 * whether FX should answer "no VPN transport" / "no VPN interface" for one opted-in
 * target so the app behaves as it would on a plain connection.
 *
 * Fail-closed by construction: the privacy master must be on, the process must be a
 * single configured target, platform/manager packages never qualify, and the target
 * must opt in explicitly. The hook never tears down, reconfigures or reroutes a tunnel;
 * it only changes what one process observes.
 */
public final class VpnDetectionPolicy {
    private VpnDetectionPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager"
    };

    /** Transport names a process may enumerate; VPN must disappear from the list. */
    public static final String VPN_TRANSPORT_NAME = "VPN";

    public static boolean shouldHideVpnDetection(boolean privacyMasterEnabled,
                                                 int processPackageCount,
                                                 String packageName,
                                                 UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        if (target == null || !target.vpnDetectionHidden) return false;
        return true;
    }

    /**
     * Drop the VPN transport bit from a capabilities long value.
     *
     * @param capabilities the original capability bitmask
     * @param vpnTransportMask the platform's TRANSPORT_VPN mask
     * @param enabled whether suppression applies to this process right now
     */
    public static long maskVpnCapabilities(long capabilities, long vpnTransportMask,
                                           boolean enabled) {
        if (!enabled) return capabilities;
        return capabilities & ~vpnTransportMask;
    }

    /**
     * Whether an interface name looks like a tunnel. Android exposes VPN links as tun
     * or ppp interfaces; only those are filtered, never a physical NIC.
     */
    public static boolean isVpnInterfaceName(String name) {
        if (name == null || name.isEmpty()) return false;
        String normalized = name.toLowerCase(java.util.Locale.ROOT);
        return normalized.startsWith("tun") || normalized.startsWith("ppp")
                || normalized.startsWith("tap") || normalized.startsWith("wg");
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
