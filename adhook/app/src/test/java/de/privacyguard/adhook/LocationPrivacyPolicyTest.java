package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class LocationPrivacyPolicyTest {
    @Test public void cachedLocationRedactionIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.location,disable_passive_loc=1\n").targets.get("com.example.location");
        assertTrue(LocationPrivacyPolicy.shouldHideLastKnownLocation(true, 1, "com.example.location", target));
        assertFalse(LocationPrivacyPolicy.shouldHideLastKnownLocation(false, 1, "com.example.location", target));
        assertFalse(LocationPrivacyPolicy.shouldHideLastKnownLocation(true, 2, "com.example.location", target));
        assertFalse(LocationPrivacyPolicy.shouldHideLastKnownLocation(true, 1, "android", target));
    }
}
