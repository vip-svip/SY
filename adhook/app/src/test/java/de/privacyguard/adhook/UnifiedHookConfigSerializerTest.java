package de.privacyguard.adhook;

import org.junit.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.Assert.*;

public class UnifiedHookConfigSerializerTest {
    private static Map<String, UnifiedHookConfigParser.Target> target(boolean ads, boolean privacy) {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.app", new UnifiedHookConfigParser.Target(
                ads, false, false, false, privacy, false, false));
        return targets;
    }

    @Test
    public void roundTripsAllIndependentMasterSwitchCombinations() {
        boolean[][] combinations = {
                {true, false}, {false, true}, {false, false}, {true, true}
        };
        for (boolean[] combination : combinations) {
            String text = UnifiedHookConfigSerializer.serialize(
                    combination[0], combination[1], target(true, true));
            UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
            assertEquals(combination[0], parsed.adsEnabled);
            assertEquals(combination[1], parsed.privacyEnabled);
            assertEquals(combination[0], parsed.isAdsEnabledFor("com.example.app"));
            assertEquals(combination[1], parsed.isPrivacyEnabledFor("com.example.app"));
            assertFalse(parsed.isAdsEnabledFor("com.notselected.app"));
            assertFalse(parsed.isPrivacyEnabledFor("com.notselected.app"));
        }
    }

    @Test
    public void outputIsDeterministicAndSortsPackageNames() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("org.example.zed", new UnifiedHookConfigParser.Target(false, true, false, false, false, false, false));
        targets.put("com.example.alpha", new UnifiedHookConfigParser.Target(true, false, false, false, true, false, false));
        String first = UnifiedHookConfigSerializer.serialize(true, true, targets);
        String second = UnifiedHookConfigSerializer.serialize(true, true, targets);
        assertEquals(first, second);
        assertTrue(first.indexOf("com.example.alpha") < first.indexOf("org.example.zed"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesProtectedSystemPackages() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("android", new UnifiedHookConfigParser.Target(false, false, false, false, true, false, false));
        UnifiedHookConfigSerializer.serialize(false, true, targets);
    }

    @Test(expected = IllegalArgumentException.class)
    public void refusesNullTargetRows() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.app", null);
        UnifiedHookConfigSerializer.serialize(true, false, targets);
    }

    @Test
    public void privacyOnlyTargetDoesNotEnableAdsButCanEnablePrivacy() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.privacyonly",
                new UnifiedHookConfigParser.Target(false, false, false, false, true, false, false));

        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);

        assertFalse(parsed.isAdsEnabledFor("com.example.privacyonly"));
        assertTrue(parsed.isPrivacyEnabledFor("com.example.privacyonly"));
        assertFalse(parsed.isPrivacyEnabledFor("com.example.other"));
    }

    @Test
    public void serializerRoundTripsExifRedactionIndependently() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.exif", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, true, false));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
        assertTrue(parsed.isExifStripEnabledFor("com.example.exif"));
        assertFalse(parsed.isPrivacyEnabledFor("com.example.exif"));
        assertTrue(text.contains("exif_strip=1"));
    }

    @Test
    public void serializerRoundTripsClipboardReadBlockIndependently() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.clip", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);
        assertTrue(parsed.isClipboardReadBlockedFor("com.example.clip"));
        assertTrue(text.contains("clipboard_read_block=1"));
        assertFalse(parsed.isClipboardReadBlockedFor("com.example.other"));
    }

    @Test
    public void disabledPrivacyMasterOverridesPerAppPrivacyFlag() {
        String text = UnifiedHookConfigSerializer.serialize(true, false, target(true, true));
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(text);

        assertTrue(parsed.isAdsEnabledFor("com.example.app"));
        assertFalse(parsed.isPrivacyEnabledFor("com.example.app"));
    }

    @Test
    public void legacyAdsConfigNeverEnablesPrivacy() {
        String legacy = "hook_ads_enabled=1\n[list:hook_targets]\n"
                + "com.example.app,splash=1,feed=0,overlay=0,member_diag=0|Example|1\n";
        UnifiedHookConfigParser.Result parsed = UnifiedHookConfigParser.parse(legacy);

        assertTrue(parsed.isAdsEnabledFor("com.example.app"));
        assertFalse(parsed.privacyEnabled);
        assertFalse(parsed.isPrivacyEnabledFor("com.example.app"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void parserRejectsDuplicateTargetFeature() {
        UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=1\nprivacy_enabled=1\n"
                + "[list:targets]\ncom.example.app,ads_splash=1,ads_splash=0\n");
    }

    @Test(expected = IllegalArgumentException.class)
    public void parserRejectsConfigOver64KiB() {
        StringBuilder oversized = new StringBuilder("schema_version=1\nads_enabled=1\n"
                + "privacy_enabled=0\n[list:targets]\n");
        while (oversized.length() <= 65536) oversized.append("#padding\n");
        UnifiedHookConfigParser.parse(oversized.toString());
    }

    @Test
    public void serializerRoundTripsAllSixSensorFlags() {
        Map<String, UnifiedHookConfigParser.Target> targets = new LinkedHashMap<>();
        targets.put("com.example.sensors", new UnifiedHookConfigParser.Target(
                false, false, false, false, false, false, false, true, true, true, true, true, true, true));
        String text = UnifiedHookConfigSerializer.serialize(false, true, targets);
        UnifiedHookConfigParser.Target t = UnifiedHookConfigParser.parse(text).targets.get("com.example.sensors");
        assertTrue(t.sensorAccel && t.sensorGyro && t.sensorLight && t.sensorMagnet && t.sensorPressure && t.sensorProx);
        assertTrue(text.contains("sensor_prox=1"));
        assertTrue(text.contains("sensor_rate_limit=1"));
    }

}
