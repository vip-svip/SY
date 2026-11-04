package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public final class UnifiedHookLocationConfigTest {
    @Test public void parsesPerTargetLocationSimulationAndAccuracy() {
        UnifiedHookConfigParser.Target target = parse(
                "com.example.gps,location_simulate=1,location_lat=31.230378,"
                        + "location_lon=121.473658,location_accuracy=12.5")
                .targets.get("com.example.gps");
        assertTrue(target.locationSimulation);
        assertEquals(31.230378d, target.simulatedLatitude, 0.0000001d);
        assertEquals(121.473658d, target.simulatedLongitude, 0.0000001d);
        assertEquals(12.5f, target.simulatedAccuracy, 0.0001f);
    }

    @Test public void defaultAccuracyIsFiveMetersWhenOmitted() {
        UnifiedHookConfigParser.Target target = parse(
                "com.example.gps,location_simulate=1,location_lat=0,location_lon=0")
                .targets.get("com.example.gps");
        assertEquals(5f, target.simulatedAccuracy, 0.0001f);
    }

    @Test public void providerEnabledSimulationIsIndependentOfCoordinateSimulation() {
        UnifiedHookConfigParser.Target target = parse(
                "com.example.gps,location_provider_enabled_simulate=1")
                .targets.get("com.example.gps");
        assertTrue(target.locationProviderEnabledSimulation);
        assertFalse(target.locationSimulation);
    }

    @Test public void serializerRoundTripsCoordinateAndProviderFlags() {
        UnifiedHookConfigParser.Result original = parse(
                "com.example.gps,location_simulate=1,location_lat=35.6,"
                        + "location_lon=139.7,location_accuracy=8.25,"
                        + "location_provider_enabled_simulate=1");
        String encoded = UnifiedHookConfigSerializer.serialize(false, false, original.targets);
        UnifiedHookConfigParser.Target restored = UnifiedHookConfigParser.parse(encoded)
                .targets.get("com.example.gps");
        assertTrue(restored.locationSimulation);
        assertTrue(restored.locationProviderEnabledSimulation);
        assertEquals(35.6d, restored.simulatedLatitude, 0.0000001d);
        assertEquals(139.7d, restored.simulatedLongitude, 0.0000001d);
        assertEquals(8.25f, restored.simulatedAccuracy, 0.0001f);
    }

    @Test public void rejectsCoordinatesOrAccuracyWithoutSimulationFlag() {
        invalid("com.example.gps,location_lat=1,location_lon=2");
        invalid("com.example.gps,location_accuracy=5");
    }

    @Test public void rejectsSimulationWithoutBothCoordinates() {
        invalid("com.example.gps,location_simulate=1,location_lat=1");
        invalid("com.example.gps,location_simulate=1,location_lon=2");
    }

    @Test public void rejectsInvalidCoordinateAndAccuracyRanges() {
        invalid("com.example.gps,location_simulate=1,location_lat=90.1,location_lon=0");
        invalid("com.example.gps,location_simulate=1,location_lat=0,location_lon=180.1");
        invalid("com.example.gps,location_simulate=1,location_lat=0,location_lon=0,location_accuracy=1000.1");
        invalid("com.example.gps,location_simulate=1,location_lat=NaN,location_lon=0");
        invalid("com.example.gps,location_simulate=1,location_lat=0,location_lon=0,location_accuracy=Infinity");
    }

    @Test public void rejectsLocationSimulationWhenLocationAccessIsBlocked() {
        invalid("com.example.gps,location_simulate=1,location_lat=1,location_lon=2,location_access_block=1");
        invalid("com.example.gps,location_provider_enabled_simulate=1,location_access_block=1");
    }

    @Test public void legacyAdConfigNeverEnablesLocationSimulation() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "hook_ads_enabled=1\n[list:hook_targets]\ncom.example.gps,splash=1\n")
                .targets.get("com.example.gps");
        assertFalse(target.locationSimulation);
        assertFalse(target.locationProviderEnabledSimulation);
    }

    private static UnifiedHookConfigParser.Result parse(String row) {
        return UnifiedHookConfigParser.parse("schema_version=1\nads_enabled=0\n"
                + "privacy_enabled=0\n[list:targets]\n" + row + "\n");
    }

    private static void invalid(String row) {
        try {
            parse(row);
            fail("Expected invalid GPS config to be rejected: " + row);
        } catch (IllegalArgumentException expected) {
            // Expected fail-closed parser validation.
        }
    }
}
