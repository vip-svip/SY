package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

/**
 * Contract tests for the widened VIP entitlement surface.
 *
 * The original implementation covered boolean entitlement getters, BillingClient results
 * and persisted preference flags. Real apps also gate premium behind subscription validity,
 * expiry timestamps, server-issued tokens, license verification, ad-removal flags and
 * integer tier getters - all of which were untouched, so a VIP feature stayed locked.
 *
 * These tests pin both the new coverage and the two rules that keep it safe: a length-2
 * method name is not evidence of an entitlement, and a negative marker always wins.
 */
public final class VipUnlockSurfaceTest {

    @Test public void lengthTwoNameIsNotEntitlement() {
        // The previous matcher returned true for any name of length <= 2, which treated
        // every compact boolean getter as premium and unlocked unrelated state.
        assertFalse(VipUnlockPolicy.isEntitlementGetter("ab"));
        assertFalse(VipUnlockPolicy.isEntitlementGetter("a"));
        assertTrue(VipUnlockPolicy.isEntitlementGetter("isVip"));
    }

    @Test public void negativeMarkersAlwaysWin() {
        assertFalse(VipUnlockPolicy.isEntitlementGetter("isNotVip"));
        assertFalse(VipUnlockPolicy.isEntitlementGetter("hasNoPremium"));
        assertFalse(VipUnlockPolicy.isEntitlementGetter("isExpiredVip"));
        assertFalse(VipUnlockPolicy.isValidityGetter("isNotActive"));
        assertFalse(VipUnlockPolicy.isAdFreeGetter("isNotAdFree"));
    }

    @Test public void recognisesValidityAndExpiryGetters() {
        assertTrue(VipUnlockPolicy.isValidityGetter("isActive"));
        assertTrue(VipUnlockPolicy.isValidityGetter("isValid"));
        assertTrue(VipUnlockPolicy.isValidityGetter("isAvailable"));
        assertTrue(VipUnlockPolicy.isExpiryGetter("isExpired"));
        assertTrue(VipUnlockPolicy.isExpiryGetter("hasExpired"));
        assertTrue(VipUnlockPolicy.isExpireTimeGetter("getExpireTime"));
        assertTrue(VipUnlockPolicy.isExpireTimeGetter("daysRemaining"));
        assertTrue(VipUnlockPolicy.isExpireTimeGetter("getDaysLeft"));
        assertFalse(VipUnlockPolicy.isExpireTimeGetter("getName"));
    }

    @Test public void recognisesTokenAndLicenseGetters() {
        assertTrue(VipUnlockPolicy.isTokenGetter("getVipToken"));
        assertTrue(VipUnlockPolicy.isTokenGetter("getLicense"));
        assertTrue(VipUnlockPolicy.isTokenGetter("getReceipt"));
        assertFalse(VipUnlockPolicy.isTokenGetter("getTitle"));
        assertTrue(VipUnlockPolicy.isLicenseVerifyMethod("verifyLicense"));
        assertTrue(VipUnlockPolicy.isLicenseVerifyMethod("checkReceipt"));
        assertTrue(VipUnlockPolicy.isLicenseVerifyMethod("isLicenseValid"));
        assertFalse(VipUnlockPolicy.isLicenseVerifyMethod("verifyName"));
    }

    @Test public void recognisesAdFreeAndTierGetters() {
        assertTrue(VipUnlockPolicy.isAdFreeGetter("isAdFree"));
        assertTrue(VipUnlockPolicy.isAdFreeGetter("hasNoAds"));
        assertTrue(VipUnlockPolicy.isAdFreeGetter("shouldShowAds"));
        assertTrue(VipUnlockPolicy.isAdFreeGetter("isAdRemoved"));
        assertFalse(VipUnlockPolicy.isAdFreeGetter("isAdmin"));
        assertTrue(VipUnlockPolicy.isTierGetter("getVipLevel"));
        assertTrue(VipUnlockPolicy.isTierGetter("getUserType"));
        assertTrue(VipUnlockPolicy.isTierGetter("getMemberLevel"));
        assertFalse(VipUnlockPolicy.isTierGetter("getLevel"));
    }

    @Test public void simulatedValuesAreUsable() {
        assertEquals(1, VipUnlockPolicy.PREMIUM_TIER);
        assertNotNull(VipUnlockPolicy.SIMULATED_TOKEN);
        // Long enough that an "empty token means free user" branch cannot fire.
        assertTrue(VipUnlockPolicy.SIMULATED_TOKEN.length() >= 32);
        assertFalse(VipUnlockPolicy.SIMULATED_TOKEN.isEmpty());
    }

    @Test public void gateStaysFailClosed() {
        UnifiedHookConfigParser.Target opted = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.app,privacy=1,vip_unlock=1\n")
                .targets.get("com.example.app");
        assertNotNull(opted);
        assertTrue(VipUnlockPolicy.shouldUnlockVip(true, 1, "com.example.app", opted));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(false, 1, "com.example.app", opted));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 2, "com.example.app", opted));
        // The platform, FX itself and the store never unlock.
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "android", opted));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "com.android.vending", opted));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "de.privacyguard.adhook", opted));
    }
}
