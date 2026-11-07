package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class SystemSurfacePrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.systemsurface," + flags + "\n").targets.get("com.example.systemsurface");
    }

    @Test public void usageAndAccessibilityFlagsAreIndependent() {
        UnifiedHookConfigParser.Target t = target("usagestats_off=1,a11y_hide=0");
        assertTrue(SystemSurfacePrivacyPolicy.shouldHideUsageStats(true, 1, "com.example.systemsurface", t));
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideAccessibilityServices(true, 1, "com.example.systemsurface", t));
    }

    @Test public void serviceEnumerationRequiresMasterAndSinglePackage() {
        UnifiedHookConfigParser.Target t = target("usagestats_off=1,a11y_hide=1");
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideUsageStats(false, 1, "com.example.systemsurface", t));
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideUsageStats(true, 2, "com.example.systemsurface", t));
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideAccessibilityServices(true, 2, "com.example.systemsurface", t));
    }

    @Test public void protectedPackagesFailOpen() {
        UnifiedHookConfigParser.Target t = target("usagestats_off=1,a11y_hide=1");
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideUsageStats(true, 1, "android", t));
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideAccessibilityServices(true, 1, "org.lsposed.manager", t));
        assertFalse(SystemSurfacePrivacyPolicy.shouldHideUsageStats(true, 1, null, t));
    }
}
