package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

/**
 * Contract test for the exact row shape `gen_xposed_conf.sh` emits into
 * [list:targets]. The generator and the parser used to disagree: the generator only
 * accepted legacy `splash/feed/overlay` and ten boolean keys, so modern rows were
 * dropped before the runtime ever saw them. This test pins the generated row and
 * proves the parser accepts every forwarded feature.
 */
public final class GeneratedTargetRowContractTest {

    /** Shape emitted by the upgraded hook_targets stage (verified by gen_final.sh). */
    private static final String GENERATED_ROW =
            "com.example.vip,ads_splash=1,ads_feed=0,ads_overlay=0,member_diag=0,privacy=1,"
          + "region_hidden=0,vpn_hidden=1,media_hidden=0,usage_hidden=0,device_profile=0,"
          + "location_lat=31.230378,location_lon=121.473658,location_accuracy=12.5,"
          + "app_version_value=9.9.9,vip_unlock=1,fake_app_version=1,location_simulate=1";

    private static UnifiedHookConfigParser.Target parseRow(String row) {
        UnifiedHookConfigParser.Result result = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=1\nprivacy_enabled=1\n[list:targets]\n" + row + "\n");
        assertNotNull(result);
        return result.targets.get("com.example.vip");
    }

    @Test public void generatorRowIsAcceptedWithEveryForwardedFeature() {
        UnifiedHookConfigParser.Target target = parseRow(GENERATED_ROW);
        assertNotNull("generated row must parse", target);
        assertTrue(target.splash);
        assertTrue(target.privacy);
        assertTrue(target.vpnDetectionHidden);
        assertTrue(target.vipUnlock);
        assertTrue(target.fakeAppVersion);
        assertTrue(target.locationSimulation);
        assertEquals(31.230378d, target.simulatedLatitude, 0.0000001d);
        assertEquals(121.473658d, target.simulatedLongitude, 0.0000001d);
        assertEquals(12.5f, target.simulatedAccuracy, 0.0001f);
        assertEquals("9.9.9", target.simulatedAppVersion);
    }

    @Test public void generatorRowIsNotMarkedActiveWithoutAnyFeature() {
        // A row with every switch at 0 must be rejected by the parser, matching the
        // generator's own "at least one feature" rule.
        String empty = "com.example.vip,ads_splash=0,ads_feed=0,ads_overlay=0,member_diag=0,"
                + "privacy=0,region_hidden=0,vpn_hidden=0,media_hidden=0,usage_hidden=0,"
                + "device_profile=0";
        UnifiedHookConfigParser.Target target = parseRow(empty);
        assertNotNull("parser keeps the row but it carries no enabled feature", target);
        assertFalse(target.enabled());
        assertFalse(target.privacy);
    }

    @Test public void serializedRowRoundTripsThroughTheParser() {
        UnifiedHookConfigParser.Target target = parseRow(GENERATED_ROW);
        String encoded = UnifiedHookConfigSerializer.serialize(true, true,
                java.util.Collections.singletonMap("com.example.vip", target));
        UnifiedHookConfigParser.Result reparsed = UnifiedHookConfigParser.parse(encoded);
        UnifiedHookConfigParser.Target restored = reparsed.targets.get("com.example.vip");
        assertNotNull(restored);
        assertTrue(restored.vipUnlock);
        assertTrue(restored.fakeAppVersion);
        assertEquals("9.9.9", restored.simulatedAppVersion);
        assertTrue(restored.locationSimulation);
        assertTrue(restored.vpnDetectionHidden);
    }

    @Test public void outOfRangeCoordinatesStillFailClosed() {
        String bad = "com.example.vip,privacy=1,location_simulate=1,"
                + "location_lat=91,location_lon=0";
        try {
            parseRow(bad);
            throw new AssertionError("out-of-range latitude must be rejected");
        } catch (IllegalArgumentException expected) {
            assertTrue(expected.getMessage() != null);
        }
    }
}
