package de.privacyguard.adhook;

import android.location.Location;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

/**
 * Contract tests for the real location injection and premium unlocking policies.
 *
 * These assert the observable behaviour the hooks rely on: an injected fix must carry
 * the configured coordinates with a usable accuracy, and the unlock gate must stay
 * fail-closed for platform / store packages and single-package processes only.
 */
public final class VipUnlockAndLocationInjectionTest {

    private static UnifiedHookConfigParser.Target unlockTarget(boolean vipUnlock) {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.premium,privacy=1,"
                        + (vipUnlock ? "vip_unlock=1" : "vip_unlock=0") + "\n")
                .targets.get("com.example.premium");
        assertNotNull(target);
        return target;
    }

    private static UnifiedHookConfigParser.Target locationTarget(
            String coords, String extra) {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.gps,privacy=1,location_simulate=1," + coords
                        + (extra == null ? "" : "," + extra) + "\n")
                .targets.get("com.example.gps");
        assertNotNull(target);
        return target;
    }

    @Test public void unlockRequiresMasterSinglePackageAndOptIn() {
        UnifiedHookConfigParser.Target target = unlockTarget(true);
        assertTrue(VipUnlockPolicy.shouldUnlockVip(true, 1, "com.example.premium", target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(false, 1, "com.example.premium", target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 2, "com.example.premium", target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "android", target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "com.android.vending", target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "org.lsposed.manager", target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, null, target));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "com.example.premium", null));
        assertFalse(VipUnlockPolicy.shouldUnlockVip(true, 1, "com.example.premium",
                unlockTarget(false)));
    }

    @Test public void entitlementGetterNamesAreRecognised() {
        for (String name : new String[]{"isVip", "hasPremium", "isMember", "isPro",
                "isSubscribed", "isPurchased", "hasEntitlement", "isLicensed", "isLifetime",
                "getFullVersion", "isUnlocked"}) {
            assertTrue(name, VipUnlockPolicy.isEntitlementGetter(name));
        }
        for (String name : new String[]{"isExpired", "isRevoked", "isCancelled",
                "isTrial", "isFree", "isAdFree", "isNotVip"}) {
            assertFalse(name, VipUnlockPolicy.isEntitlementGetter(name));
        }
        assertTrue("compact obfuscated getter", VipUnlockPolicy.isEntitlementGetter("a"));
        assertFalse(VipUnlockPolicy.isEntitlementGetter(null));
        assertFalse(VipUnlockPolicy.isEntitlementGetter(""));
    }

    @Test public void preferenceKeysUnlockOnlyWhenStoredValueIsFalse() {
        assertTrue(VipUnlockPolicy.shouldUnlockPreferenceKey("is_vip", false));
        assertTrue(VipUnlockPolicy.shouldUnlockPreferenceKey("premium_user", false));
        assertTrue(VipUnlockPolicy.shouldUnlockPreferenceKey("has_subscription", false));
        // Already unlocked: never rewrite a true value.
        assertFalse(VipUnlockPolicy.shouldUnlockPreferenceKey("is_vip", true));
        // Negative-state keys keep their stored value.
        assertFalse(VipUnlockPolicy.shouldUnlockPreferenceKey("vip_expired", false));
        assertFalse(VipUnlockPolicy.shouldUnlockPreferenceKey("subscription_cancelled", false));
        assertFalse(VipUnlockPolicy.shouldUnlockPreferenceKey(null, false));
        assertFalse(VipUnlockPolicy.shouldUnlockPreferenceKey("theme_dark", false));
    }

    @Test public void injectedFixCarriesConfiguredCoordinatesAndUsableAccuracy() {
        UnifiedHookConfigParser.Target target = locationTarget(
                "location_lat=31.230378,location_lon=121.473658,location_accuracy=12.5", null);
        LocationInjectionPolicy.FixValues fix =
                LocationInjectionPolicy.resolveFixValues(target, "gps");
        assertNotNull(fix);
        assertEquals(31.230378d, fix.latitude, 0.0000001d);
        assertEquals(121.473658d, fix.longitude, 0.0000001d);
        assertEquals(12.5f, fix.accuracy, 0.0001f);
        assertEquals("gps", fix.provider);
        // A stationary injected fix must not claim motion.
        assertEquals(0f, fix.speed, 0.0001f);
        assertEquals(0f, fix.bearing, 0.0001f);
        assertEquals(0d, fix.altitude, 0.0001d);
    }

    @Test public void injectedFixDefaultsAccuracyWithoutBreakingRange() {
        UnifiedHookConfigParser.Target target = locationTarget(
                "location_lat=0,location_lon=0", null);
        LocationInjectionPolicy.FixValues fix =
                LocationInjectionPolicy.resolveFixValues(target, null);
        assertEquals(5f, fix.accuracy, 0.0001f);
        assertEquals(LocationInjectionPolicy.DEFAULT_PROVIDER, fix.provider);
        // (0,0) is a legitimate coordinate and must survive unchanged.
        assertEquals(0d, fix.latitude, 0.0001d);
        assertEquals(0d, fix.longitude, 0.0001d);
    }

    @Test public void injectionGateFailsClosed() {
        UnifiedHookConfigParser.Target target = locationTarget(
                "location_lat=31.2,location_lon=121.4", null);
        assertTrue(LocationInjectionPolicy.shouldInjectLocation(true, 1, "com.example.gps", target));
        assertFalse(LocationInjectionPolicy.shouldInjectLocation(false, 1, "com.example.gps", target));
        assertFalse(LocationInjectionPolicy.shouldInjectLocation(true, 2, "com.example.gps", target));
        assertFalse(LocationInjectionPolicy.shouldInjectLocation(true, 1, "android", target));
        assertFalse(LocationInjectionPolicy.shouldInjectLocation(true, 1, "com.example.gps", null));
        // A target that blocks location cannot also inject it. The parser already
        // rejects that combination, so this asserts the policy guard independently.
        UnifiedHookConfigParser.Target blocked = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.blocked,privacy=1,location_access_block=1\n")
                .targets.get("com.example.blocked");
        assertNotNull(blocked);
        assertFalse(LocationInjectionPolicy.shouldInjectLocation(true, 1,
                "com.example.gps", blocked));
    }

    @Test public void coordinateValidationRejectsImpossibleValues() {
        assertTrue(LocationInjectionPolicy.validCoordinate(90d, 180d));
        assertTrue(LocationInjectionPolicy.validCoordinate(-90d, -180d));
        assertTrue(LocationInjectionPolicy.validCoordinate(0d, 0d));
        assertFalse(LocationInjectionPolicy.validCoordinate(Double.NaN, 0d));
        assertFalse(LocationInjectionPolicy.validCoordinate(0d, Double.NaN));
        assertFalse(LocationInjectionPolicy.validCoordinate(91d, 0d));
        assertFalse(LocationInjectionPolicy.validCoordinate(0d, 181d));
        assertTrue(LocationInjectionPolicy.validAccuracy(5f));
        assertTrue(LocationInjectionPolicy.validAccuracy(0f));
        assertFalse(LocationInjectionPolicy.validAccuracy(Float.NaN));
        assertFalse(LocationInjectionPolicy.validAccuracy(-1f));
        assertFalse(LocationInjectionPolicy.validAccuracy(1001f));
    }

    @Test public void billingIntegersMapToCompletedPurchase() {
        assertEquals(0, VipUnlockPolicy.BILLING_OK);
        assertEquals(0, VipUnlockPolicy.PURCHASE_STATE_PURCHASED);
        assertTrue(VipUnlockPolicy.isPurchaseStateGetter("getPurchaseState"));
        assertFalse(VipUnlockPolicy.isPurchaseStateGetter("getSku"));
    }
}
