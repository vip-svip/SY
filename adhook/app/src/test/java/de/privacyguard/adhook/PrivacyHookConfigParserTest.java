package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class PrivacyHookConfigParserTest {
    @Test public void parsesLegacySectionsAndValues() {
        PrivacyHookConfigParser.Result result = PrivacyHookConfigParser.parse(
                "lsposed_enabled=1\nlsposed_profile=standard\n"
                + "[conf:lsposed_scope]\ncom.example.*\n"
                + "[list:fs_rootlist]\n/sbin/su\n");
        assertTrue(result.enabled("lsposed_enabled"));
        assertTrue(result.enabled("hide_su"));
        assertFalse(result.enabled("block_pm_query"));
        assertEquals("/sbin/su", result.lines("list:fs_rootlist").get(0));
        assertTrue(result.inScope("com.example.app"));
        assertFalse(result.inScope("org.other.app"));
    }

    @Test public void disabledMasterGatesAllFeaturesAndProfiles() {
        PrivacyHookConfigParser.Result result = PrivacyHookConfigParser.parse(
                "lsposed_enabled=0\nlsposed_profile=aggressive\nspoof_model=1\nhide_ksu=1\n");
        assertFalse(result.enabled("spoof_model"));
        assertFalse(result.enabled("hide_ksu"));
    }

    @Test public void compatProfileDisablesRiskyKeys() {
        PrivacyHookConfigParser.Result result = PrivacyHookConfigParser.parse(
                "lsposed_enabled=1\nlsposed_profile=compat\nblock_pm_query=1\n");
        assertFalse(result.enabled("block_pm_query"));
        assertTrue(result.enabled("spoof_model"));
    }

    @Test public void aggressiveProfileEnablesRiskyKeys() {
        PrivacyHookConfigParser.Result result = PrivacyHookConfigParser.parse(
                "lsposed_enabled=1\nlsposed_profile=aggressive\n");
        assertTrue(result.enabled("hide_ksu"));
    }

    @Test public void neverHookPackagesAreRejectedFromScope() {
        PrivacyHookConfigParser.Result result = PrivacyHookConfigParser.parse(
                "lsposed_enabled=1\n");
        assertFalse(result.inScope("android"));
        assertFalse(result.inScope("de.privacyguard.adhook"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void missingMasterSwitchFailsClosed() {
        PrivacyHookConfigParser.parse("spoof_model=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void duplicateTopLevelSwitchIsRejected() {
        PrivacyHookConfigParser.parse("lsposed_enabled=1\nlsposed_enabled=0\n");
    }
}
