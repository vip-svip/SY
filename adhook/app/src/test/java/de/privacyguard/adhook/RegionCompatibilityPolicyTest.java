package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class RegionCompatibilityPolicyTest {
    @Test public void regionDiagnosticsAreReadOnlyAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=0\n[list:targets]\n" +
                "com.example.region,region_diag=1\n").targets.get("com.example.region");
        assertTrue(RegionCompatibilityPolicy.shouldObserveRegion(1, "com.example.region", target));
        assertFalse(RegionCompatibilityPolicy.shouldObserveRegion(2, "com.example.region", target));
        assertFalse(RegionCompatibilityPolicy.shouldObserveRegion(1, "android", target));
        assertFalse(RegionCompatibilityPolicy.shouldObserveRegion(1, "com.example.other", target));
    }
}
