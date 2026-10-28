package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class UnifiedHookConfigParserTest {
    private static final String VALID =
            "schema_version=1\n" +
            "ads_enabled=1\n" +
            "privacy_enabled=0\n" +
            "[list:targets]\n" +
            "com.example.app,ads_splash=1,ads_feed=0,ads_overlay=1,member_diag=0,privacy=1\n";

    @Test
    public void parsesIndependentMasterSwitchesAndPerPackageFeatures() {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(VALID);
        assertTrue(result.adsEnabled);
        assertFalse(result.privacyEnabled);
        UnifiedHookConfigParser.Target target = result.targets.get("com.example.app");
        assertNotNull(target);
        assertTrue(target.splash);
        assertFalse(target.feed);
        assertTrue(target.overlay);
        assertFalse(target.memberDiag);
        assertTrue(target.privacy);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsMissingRequiredSwitch() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\n[list:targets]\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDuplicatePackageTransactionally() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,privacy=1\ncom.example.app,ads_feed=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsProtectedPackages() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\nandroid,privacy=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsUnknownFeatures() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,make_vip=1\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsOversizedConfig() {
        StringBuilder text = new StringBuilder(70000);
        while (text.length() < 66000) text.append('#').append('x').append('\n');
        UnifiedHookConfigParser.parse(text.toString());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsDuplicateFeatureKeys() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n" +
                "[list:targets]\ncom.example.app,privacy=1,privacy=0\n");
    }
}
