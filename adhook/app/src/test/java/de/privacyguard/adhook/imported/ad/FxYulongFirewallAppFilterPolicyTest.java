package de.privacyguard.adhook.imported.ad;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/** Regression tests for user/system firewall list filtering. */
public class FxYulongFirewallAppFilterPolicyTest {
    private static final int FLAG_SYSTEM = 1;
    private static final int FLAG_UPDATED_SYSTEM_APP = 128;

    @Test
    public void allAppsModeIncludesBothClasses() {
        assertTrue(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.ALL_APPS, 0));
        assertTrue(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.ALL_APPS, FLAG_SYSTEM));
    }

    @Test
    public void userAppsModeExcludesBothSystemFlagVariants() {
        assertTrue(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.USER_APPS, 0));
        assertFalse(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.USER_APPS, FLAG_SYSTEM));
        assertFalse(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.USER_APPS, FLAG_UPDATED_SYSTEM_APP));
        assertFalse(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.USER_APPS,
                FLAG_SYSTEM | FLAG_UPDATED_SYSTEM_APP));
    }

    @Test
    public void systemAppsModeIncludesBothSystemFlagVariantsOnly() {
        assertFalse(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.SYSTEM_APPS, 0));
        assertTrue(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.SYSTEM_APPS, FLAG_SYSTEM));
        assertTrue(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.SYSTEM_APPS, FLAG_UPDATED_SYSTEM_APP));
        assertTrue(FxYulongFirewallAppFilterPolicy.includes(
                FxYulongFirewallAppFilterPolicy.SYSTEM_APPS,
                FLAG_SYSTEM | FLAG_UPDATED_SYSTEM_APP));
    }

    @Test
    public void unknownModeFailsClosed() {
        assertFalse(FxYulongFirewallAppFilterPolicy.includes(99, 0));
    }
}
