package de.privacyguard.adhook;

/**
 * Neutralise the inputs an anti-fraud SDK feeds into its consistency cross-checks.
 *
 * Research basis: s1mb1o/vpn-detector-android `ConsistencyChecks.kt` compares, for each
 * session, these pairs and raises a HARD or SOFT verdict when they disagree:
 *
 *   sim_vs_ip        SIM country            vs egress country
 *   net_vs_ip        network country        vs egress country
 *   carrier_vs_asn   network operator name  vs egress ASN org
 *   mcc_vs_ip        network operator MCC   vs egress country
 *   locale_vs_ip     Locale country         vs egress country
 *   lang_vs_ip       Locale language        vs egress country
 *   tz_vs_ip         TimeZone id            vs egress timezone
 *   ru_apps          installed RU markers   vs egress country
 *   v4_v6_exit_split IPv4 exit              vs IPv6 exit
 *   dns_vs_exit      DNS resolver egress    vs HTTP egress
 *
 * The SDK does not rely on a single "VPN is up" bit, so masking one getter is not enough:
 * the *comparison baseline* has to be collapsed. This class decides which inputs are
 * masked so every brace of the comparison reads the same neutral value.
 *
 * Masking is per-target, opt-in, and only applies while the carrier/region or recon
 * switches are on. It is pure logic, so the whole decision table is unit-testable.
 */
public final class ConsistencyBaselinePolicy {
    private ConsistencyBaselinePolicy() { }

    /** The neutral country code reported when the comparison baseline is collapsed. */
    public static final String NEUTRAL_COUNTRY = "";
    /** The neutral timezone id. */
    public static final String NEUTRAL_TIMEZONE = "UTC";
    /** The neutral MCC (3 digits; empty means "no SIM country"). */
    public static final String NEUTRAL_MCC = "";

    /** Which consistency input a read belongs to. */
    public enum Field {
        SIM_COUNTRY,
        NETWORK_COUNTRY,
        NETWORK_OPERATOR_NAME,
        MCC,
        LOCALE_COUNTRY,
        LOCALE_LANGUAGE,
        TIMEZONE_ID,
        TIMEZONE_OFFSET,
        SIM_STATE
    }

    /**
     * Should this field be collapsed to the neutral baseline?
     *
     * Collapsing is all-or-nothing per process: a partial mask (for example hiding SIM
     * country but leaving the network country) leaves a mismatch the SDK can still see,
     * which is worse than not masking at all because it looks like an inconsistent
     * device rather than a masked one.
     */
    public static boolean shouldCollapse(boolean privacyMasterEnabled,
                                         int processPackageCount,
                                         String packageName,
                                         UnifiedHookConfigParser.Target target,
                                         Field field) {
        if (field == null) return false;
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        if (target == null) return false;
        // Either hardening switch collapses the whole baseline, because both exist to
        // stop cross-correlation rather than to hide one individual getter.
        boolean collapse = target.carrierCollectionBlock || target.policeReconBlock;
        if (!collapse) return false;
        // A target that asked for a simulated fix keeps its own coordinates; the region
        // baseline still has to line up, so every field collapses together.
        return true;
    }

    /** The value to report for a collapsed field, or null when it should pass through. */
    public static String neutralValue(boolean collapse, Field field, String fallback) {
        if (!collapse || field == null) return fallback;
        switch (field) {
            case SIM_COUNTRY:
            case NETWORK_COUNTRY:
            case LOCALE_COUNTRY:
                return NEUTRAL_COUNTRY;
            case NETWORK_OPERATOR_NAME:
            case LOCALE_LANGUAGE:
                return NEUTRAL_COUNTRY;
            case MCC:
                return NEUTRAL_MCC;
            case TIMEZONE_ID:
                return NEUTRAL_TIMEZONE;
            default:
                return fallback;
        }
    }

    /** Numeric neutral value for the numeric fields. */
    public static int neutralInt(boolean collapse, Field field, int fallback) {
        if (!collapse || field == null) return fallback;
        if (field == Field.TIMEZONE_OFFSET) return 0;
        // SIM_STATE_UNKNOWN: no SIM state to correlate with the egress.
        if (field == Field.SIM_STATE) return 0;
        return fallback;
    }

    /**
     * Whether an installed package counts as a region marker that would contradict the
     * egress. The SDK treats three or more markers as an identity signal, so a masked
     * target must not expose the marker set at all.
     */
    public static boolean isRegionMarkerPackage(boolean collapse, String installedPackage) {
        if (!collapse) return true;  // not hidden, the SDK sees the real list
        return false;                // hidden: no marker may be observed
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        return "android".equals(packageName) || "system".equals(packageName)
                || "de.privacyguard.hook".equals(packageName)
                || "de.privacyguard.adhook".equals(packageName)
                || "org.lsposed.manager".equals(packageName);
    }
}
