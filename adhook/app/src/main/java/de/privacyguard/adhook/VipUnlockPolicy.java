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

    /** Keys that describe a *negative* state and must keep their stored value. */
    private static final String[] NEGATIVE_KEY_MARKERS = {
            "expire", "expiry", "expired", "revoked", "cancel", "canceled",
            "refund", "trial", "free", "ad_", "ads_free",
            // Explicit negations: isNotVip / has_no_premium must not read as entitled.
            "notvip", "notpremium", "notmember", "notsubscribed", "notpaid",
            "no_vip", "no_premium", "no_member", "no_subscription",
            "without", "unsubscribed", "nonsubscriber", "isnot"
    };

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
        if (normalized.length() <= 2) return true;  // obfuscated compact getter
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

    public static boolean isProtected(String packageName) {
        if (packageName == null || packageName.isEmpty()) return true;
        for (String protectedName : PROTECTED_PACKAGES) {
            if (protectedName.equals(packageName)) return true;
        }
        return false;
    }
}
