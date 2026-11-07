package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class AdvertisingIdPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target() {
        return UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                + "com.example.ads,ad_id_unify=1\n").targets.get("com.example.ads");
    }

    @Test public void requiresExplicitSinglePackageOptIn() {
        assertTrue(AdvertisingIdPrivacyPolicy.shouldUnify(true, 1, "com.example.ads", target()));
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(false, 1, "com.example.ads", target()));
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(true, 2, "com.example.ads", target()));
    }

    @Test public void protectedAndUnknownPackagesFailOpen() {
        UnifiedHookConfigParser.Target t = target();
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(true, 1, "android", t));
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(true, 1, "de.privacyguard.adhook", t));
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(true, 1, "org.lsposed.manager", t));
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(true, 1, null, t));
        assertFalse(AdvertisingIdPrivacyPolicy.shouldUnify(true, 1, "com.example.ads", null));
    }

    @Test public void syntheticIdsAreStablePackageScopedUuidValues() {
        String first = AdvertisingIdPrivacyPolicy.syntheticId("com.example.ads");
        assertNotNull(first);
        assertEquals(36, first.length());
        assertEquals(first, AdvertisingIdPrivacyPolicy.syntheticId("com.example.ads"));
        assertNotEquals(first, AdvertisingIdPrivacyPolicy.syntheticId("com.example.other"));
        assertTrue(first.matches("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"));
    }
}
