package de.privacyguard.adhook;

/**
 * Per-target gate and decision table for real VIP / in-app purchase unlocking.
 *
 * This is not a reporting shim: the installer changes what the app's own entitlement
 * code *computes*, so premium features actually open. Three cooperating surfaces:
 *
 *  1. boolean member getters (isVip / hasPremium / isPro ...) return "entitled";
 *  2. billing result codes report a completed purchase instead of SERVICE_UNAVAILABLE;
 *  3. persisted entitlement keys in the app's own SharedPreferences read "unlocked".
 *
 * Every surface stays per-target, opt-in and fail-closed, and the policy never touches
 * platform, manager or store packages.
 */
public final class VipUnlockPolicy {
    private VipUnlockPolicy() { }

    private static final String[] PROTECTED_PACKAGES = {
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook",
            "org.lsposed.manager", "com.android.vending"
    };

    /** Google Play billing response code for a completed purchase. */
    public static final int BILLING_OK = 0;

    /** Purchase state that Play reports for a completed, owned purchase. */
    public static final int PURCHASE_STATE_PURCHASED = 0;

    /** Preference keys whose boolean value grants premium access. */
    private static final String[] UNLOCK_KEY_MARKERS = {
            "vip", "premium", "member", "pro", "plus", "unlock", "unlocked",
            "subscribed", "subscription", "paid", "purchase", "purchased",
            "entitlement", "licensed", "full", "forever", "lifetime"
    };


    /** Negative words that make a name describe the ABSENCE of premium. */
    private static final String[] NEGATIVE_KEY_MARKERS = {
            "expire", "expiry", "expired", "revoked", "cancel", "canceled",
            "refund", "trial", "free", "ad_", "ads_free",
            "notvip", "notpremium", "notmember", "notsubscribed", "notpaid",
            "no_vip", "no_premium", "no_member", "no_subscription",
            "nopremium", "novip", "nomember", "nosubscription", "nosubscribe",
            "nonpremium", "nonvip", "nonmember",
            "without", "unsubscribed", "nonsubscriber", "isnot"
    };

    /** Getters whose integer result is a subscription tier; premium is a positive tier. */
    private static final String[] TIER_GETTER_MARKERS = {
            "viplevel", "memberlevel", "userlevel", "usertype", "membertype", "viptype",
            "accounttype", "plantype", "subscriptionlevel", "gradetype", "tier"
    };

    /** Getters that answer "is this subscription still valid". */
    private static final String[] VALIDITY_GETTER_MARKERS = {
            "isvalid", "isactive", "isavailable", "isenabled", "isusable",
            "isprivilege", "isopened"
    };

    /** Getters that answer "is this subscription expired"; false means still valid. */
    private static final String[] EXPIRY_GETTER_MARKERS = {
            "isexpired", "hasexpired", "hassexpired", "isoutofdate", "istrialexpired"
    };

    /** Getters returning a timestamp or a remaining-day count. */
    private static final String[] EXPIRETIME_GETTER_MARKERS = {
            "getexpiretime", "getexpiredate", "getexpiresat", "getvaliduntil",
            "getvalidto", "getendtime", "getenddate", "daysremaining", "remainingdays",
            "getremainingdays", "getdaysleft", "daysleft"
    };

    /** Getters that hand out a server-issued entitlement token. */
    private static final String[] TOKEN_GETTER_MARKERS = {
            "getviptoken", "getlicense", "getlicence", "getentitlementtoken",
            "getauthtoken", "getmembertoken", "getpurchasetoken", "getreceipt"
    };

    /** Methods that verify a license or receipt. */
    private static final String[] LICENSE_VERIFY_MARKERS = {
            "verifylicense", "checklicense", "islicensevalid", "verifyreceipt",
            "checkreceipt", "validatereceipt", "verifypurchase", "validatepurchase",
            "checkentitlement", "verifyentitlement"
    };

    /** Getters that answer "is this user ad-free". */
    private static final String[] AD_FREE_GETTER_MARKERS = {
            "isadfree", "hasnoads", "isnoads", "shouldshowads", "shoulddisplayads",
            "isadremoved", "isadsremoved", "hasremovedads", "adfree", "isnoadversion"
    };

    /** The premium tier reported by a tier getter. */
    public static final int PREMIUM_TIER = 1;

    /** A token long enough that "empty token means free user" branches are not taken. */
    public static final String SIMULATED_TOKEN =
            "fx-simulated-entitlement-0000000000000000000000000000";

    public static boolean shouldUnlockVip(boolean privacyMasterEnabled,
                                          int processPackageCount,
                                          String packageName,
                                          UnifiedHookConfigParser.Target target) {
        if (!privacyMasterEnabled || processPackageCount != 1) return false;
        if (packageName == null || packageName.isEmpty()) return false;
        if (isProtected(packageName)) return false;
        return target != null && target.vipUnlock;
    }

    /** Should a persisted boolean key be forced to "unlocked"? */
    public static boolean shouldUnlockPreferenceKey(String key, boolean storedValue) {
        if (key == null || key.isEmpty()) return false;
        if (storedValue) return false;  // already unlocked: never rewrite a true value
        String normalized = key.toLowerCase(java.util.Locale.ROOT);
        for (String negative : NEGATIVE_KEY_MARKERS) {
            if (normalized.contains(negative)) return false;
        }
        for (String marker : UNLOCK_KEY_MARKERS) {
            if (normalized.contains(marker)) return true;
        }
        return false;
    }

    /** Boolean getter names that describe an entitlement. */
    public static boolean isEntitlementGetter(String methodName) {
        if (methodName == null || methodName.isEmpty()) return false;
        String normalized = methodName.toLowerCase(java.util.Locale.ROOT);
        // A length-2 name is not evidence of an entitlement: matching on name length
        // marked every compact boolean getter as premium and unlocked unrelated
        // state. Obfuscation is covered by the marker tables plus the per-target
        // opt-in, not by a length heuristic.
        if (normalized.length() <= 2) return false;
        for (String negative : NEGATIVE_KEY_MARKERS) {
            if (normalized.contains(negative)) return false;
        }
        for (String marker : UNLOCK_KEY_MARKERS) {
            if (normalized.contains(marker)) return true;
        }
        return false;
    }

    /** Integer getter names that describe a purchase/entitlement state. */
    public static boolean isPurchaseStateGetter(String methodName) {
        if (methodName == null) return false;
        String normalized = methodName.toLowerCase(java.util.Locale.ROOT);
        return normalized.contains("purchasestate")
                || normalized.contains("entitlementstate")
                || normalized.contains("billingstate");
    }


    /** Case-insensitive marker match for surfaces that describe the PRESENCE of premium. */
    private static boolean matchesPositive(String methodName, String[] markers) {
        if (methodName == null || methodName.isEmpty()) return false;
        String normalized = methodName.toLowerCase(java.util.Locale.ROOT);
        if (normalized.length() <= 2) return false;
        for (String negative : NEGATIVE_KEY_MARKERS) {
            if (normalized.contains(negative)) return false;
        }
        return containsMarker(normalized, markers);
    }

    /**
     * Marker match for surfaces whose polarity is already encoded in the marker table.
     *
     * "free" is a negative marker for an entitlement but the defining word for an ad-free
     * getter, and "trial" is negative for premium yet part of the expiry getter we must
     * intercept. Explicit negation still wins, except for the ad-free surface where
     * hasNoAds IS the premium state.
     */
    private static boolean matchesOwnSense(String methodName, String[] markers) {
        if (methodName == null || methodName.isEmpty()) return false;
        String normalized = methodName.toLowerCase(java.util.Locale.ROOT);
        if (normalized.length() <= 2) return false;
        // An explicit negation always wins, even on the ad-free surface: isNotAdFree
        // describes the absence of the state, while hasNoAds IS the state.
        if (normalized.contains("isnot") || normalized.contains("without")) {
            return false;
        }
        // hasNoAds is the ad-free state itself, so an ad-free marker beats the generic
        // negative word "no"/"free" that would otherwise suppress it.
        boolean adFree = containsMarker(normalized, AD_FREE_GETTER_MARKERS);
        if (!adFree) {
            for (String negative : NEGATIVE_KEY_MARKERS) {
                if (normalized.contains(negative)) return false;
            }
        }
        return containsMarker(normalized, markers);
    }

    /** Shared substring test; markers are lower-case already. */
    private static boolean containsMarker(String normalized, String[] markers) {
        for (String marker : markers) {
            if (normalized.contains(marker.toLowerCase(java.util.Locale.ROOT))) return true;
        }
        return false;
    }

    /** Boolean getter naming a validity state. */
    public static boolean isValidityGetter(String methodName) {
        return matchesPositive(methodName, VALIDITY_GETTER_MARKERS);
    }

    /**
     * Boolean getter naming an expiry state; false must be reported for an active sub.
     *
     * "expired" is a negative marker for premium, so this surface cannot go through the
     * shared negation filter - that filter would reject the method it exists to intercept.
     * Only an explicit "isnot" is excluded here.
     */
    public static boolean isExpiryGetter(String methodName) {
        if (methodName == null || methodName.isEmpty()) return false;
        String normalized = methodName.toLowerCase(java.util.Locale.ROOT);
        if (normalized.length() <= 2) return false;
        if (normalized.contains("isnot") || normalized.contains("without")) return false;
        return containsMarker(normalized, EXPIRY_GETTER_MARKERS);
    }

    /** Getter returning a timestamp or remaining-day count. */
    public static boolean isExpireTimeGetter(String methodName) {
        // Same reason as the expiry getter: "expire" is a negative marker for
        // premium, so this surface matches its own markers and excludes only
        // an explicit negation.
        if (methodName == null || methodName.isEmpty()) return false;
        String normalized = methodName.toLowerCase(java.util.Locale.ROOT);
        if (normalized.length() <= 2) return false;
        if (normalized.contains("isnot") || normalized.contains("without")) return false;
        return containsMarker(normalized, EXPIRETIME_GETTER_MARKERS);
    }
    /** Method that verifies a license or receipt. */
    /** Getter returning a server-issued entitlement token. */
    public static boolean isTokenGetter(String methodName) {
        return matchesPositive(methodName, TOKEN_GETTER_MARKERS);
    }

    public static boolean isLicenseVerifyMethod(String methodName) {
        return matchesPositive(methodName, LICENSE_VERIFY_MARKERS);
    }

    /** Getter that answers "is this user ad-free". */
    public static boolean isAdFreeGetter(String methodName) {
        return matchesOwnSense(methodName, AD_FREE_GETTER_MARKERS);
    }

    /** Getter whose integer result is a subscription tier. */
    public static boolean isTierGetter(String methodName) {
        return matchesPositive(methodName, TIER_GETTER_MARKERS);
    }

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
