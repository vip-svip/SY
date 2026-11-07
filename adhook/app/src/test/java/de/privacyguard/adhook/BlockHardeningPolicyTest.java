package de.privacyguard.adhook;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

/**
 * Contract tests for the three hardening switches:
 * anti-fraud blocking, carrier-collection blocking and police-recon blocking.
 *
 * Each gate must stay fail-closed (master off, shared process, protected package,
 * missing target) and each surface must be independently answerable so a single
 * switch can be traced to the hook it drives.
 */
public final class BlockHardeningPolicyTest {

    private static UnifiedHookConfigParser.Target target(String features) {
        UnifiedHookConfigParser.Target parsed = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.app,privacy=1," + features + "\n")
                .targets.get("com.example.app");
        assertNotNull(parsed);
        return parsed;
    }

    @Test public void antiFraudGateIsFailClosed() {
        UnifiedHookConfigParser.Target t = target("anti_fraud_block=1");
        assertTrue(AntiFraudBlockPolicy.shouldBlock(true, 1, "com.example.app", t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(false, 1, "com.example.app", t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 2, "com.example.app", t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 1, "android", t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 1, "org.lsposed.manager", t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 1, "de.privacyguard.adhook", t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 1, null, t));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 1, "com.example.app", null));
        assertFalse(AntiFraudBlockPolicy.shouldBlock(true, 1, "com.example.app",
                target("anti_fraud_block=0")));
    }

    @Test public void antiFraudSurfacesAreIndependentlyGated() {
        UnifiedHookConfigParser.Target t = target("anti_fraud_block=1");
        for (AntiFraudBlockPolicy.Surface surface : AntiFraudBlockPolicy.Surface.values()) {
            boolean expected = true;
            assertTrue(surface.name(),
                    AntiFraudBlockPolicy.shouldBlockSurface(true, 1, "com.example.app", t, surface)
                            == expected);
        }
        // Location injection and location blocking contradict each other.
        UnifiedHookConfigParser.Target injecting = target(
                "anti_fraud_block=1,location_simulate=1,location_lat=1,location_lon=2");
        assertFalse(AntiFraudBlockPolicy.shouldBlockSurface(true, 1, "com.example.app",
                injecting, AntiFraudBlockPolicy.Surface.LOCATION));
    }

    @Test public void antiFraudComponentDetectionMatchesPackageOnly() {
        assertTrue(AntiFraudBlockPolicy.isAntiFraudComponent("com.android.antifraud"));
        assertTrue(AntiFraudBlockPolicy.isAntiFraudComponent("cn.gov.gjfz"));
        assertTrue(AntiFraudBlockPolicy.isAntiFraudComponent("com.example.fanzha"));
        assertFalse(AntiFraudBlockPolicy.isAntiFraudComponent("com.example.browser"));
        assertFalse(AntiFraudBlockPolicy.isAntiFraudComponent(""));
        assertFalse(AntiFraudBlockPolicy.isAntiFraudComponent(null));
    }

    @Test public void carrierGateIsFailClosed() {
        UnifiedHookConfigParser.Target t = target("carrier_collection_block=1");
        assertTrue(CarrierCollectionBlockPolicy.shouldBlock(true, 1, "com.example.app", t));
        assertFalse(CarrierCollectionBlockPolicy.shouldBlock(false, 1, "com.example.app", t));
        assertFalse(CarrierCollectionBlockPolicy.shouldBlock(true, 2, "com.example.app", t));
        assertFalse(CarrierCollectionBlockPolicy.shouldBlock(true, 1, "android", t));
        assertFalse(CarrierCollectionBlockPolicy.shouldBlock(true, 1, "com.example.app", null));
    }

    @Test public void carrierSurfacesCoverIdentityAndMetadata() {
        UnifiedHookConfigParser.Target t = target("carrier_collection_block=1");
        for (CarrierCollectionBlockPolicy.Surface surface
                : CarrierCollectionBlockPolicy.Surface.values()) {
            assertTrue(surface.name(), CarrierCollectionBlockPolicy.shouldBlockSurface(
                    true, 1, "com.example.app", t, surface));
        }
        assertTrue(CarrierCollectionBlockPolicy.isCarrierComponent("com.android.carrier"));
        assertTrue(CarrierCollectionBlockPolicy.isCarrierComponent("com.chinamobile.cmcc"));
        assertFalse(CarrierCollectionBlockPolicy.isCarrierComponent("com.example.mail"));
    }

    @Test public void policeReconGateIsFailClosed() {
        UnifiedHookConfigParser.Target t = target("police_recon_block=1");
        assertTrue(PoliceReconBlockPolicy.shouldBlock(true, 1, "com.example.app", t));
        assertFalse(PoliceReconBlockPolicy.shouldBlock(false, 1, "com.example.app", t));
        assertFalse(PoliceReconBlockPolicy.shouldBlock(true, 2, "com.example.app", t));
        assertFalse(PoliceReconBlockPolicy.shouldBlock(true, 1, "de.privacyguard.hook", t));
        assertFalse(PoliceReconBlockPolicy.shouldBlock(true, 1, "com.example.app", null));
    }

    @Test public void policeReconDefersVpnStateToTheDedicatedSwitch() {
        UnifiedHookConfigParser.Target recon = target("police_recon_block=1");
        assertTrue(PoliceReconBlockPolicy.shouldBlockSurface(true, 1, "com.example.app",
                recon, PoliceReconBlockPolicy.Surface.VPN_STATE));
        // When the dedicated VPN switch owns that surface the recon switch must not
        // create a second, competing answer.
        UnifiedHookConfigParser.Target both = target("police_recon_block=1,vpn_hidden=1");
        assertFalse(PoliceReconBlockPolicy.shouldBlockSurface(true, 1, "com.example.app",
                both, PoliceReconBlockPolicy.Surface.VPN_STATE));
        assertTrue(PoliceReconBlockPolicy.shouldBlockSurface(true, 1, "com.example.app",
                both, PoliceReconBlockPolicy.Surface.INSTALLED_PACKAGES));
    }

    @Test public void reconComponentDetectionMatchesPackageOnly() {
        assertTrue(PoliceReconBlockPolicy.isReconComponent("com.example.forensic"));
        assertTrue(PoliceReconBlockPolicy.isReconComponent("cn.gov.police"));
        assertFalse(PoliceReconBlockPolicy.isReconComponent("com.example.music"));
        assertFalse(PoliceReconBlockPolicy.isReconComponent(null));
    }

    @Test public void allThreeSwitchesRoundTripThroughTheSerializer() {
        UnifiedHookConfigParser.Target t = target(
                "anti_fraud_block=1,carrier_collection_block=1,police_recon_block=1");
        String encoded = UnifiedHookConfigSerializer.serialize(true, true,
                java.util.Collections.singletonMap("com.example.app", t));
        assertTrue(encoded.contains("anti_fraud_block=1"));
        assertTrue(encoded.contains("carrier_collection_block=1"));
        assertTrue(encoded.contains("police_recon_block=1"));
        UnifiedHookConfigParser.Target restored = UnifiedHookConfigParser.parse(encoded)
                .targets.get("com.example.app");
        assertNotNull(restored);
        assertTrue(restored.antiFraudBlock);
        assertTrue(restored.carrierCollectionBlock);
        assertTrue(restored.policeReconBlock);
    }

    @Test public void switchesDefaultOff() {
        UnifiedHookConfigParser.Target t = target("clipboard_read_block=0");
        assertFalse(t.antiFraudBlock);
        assertFalse(t.carrierCollectionBlock);
        assertFalse(t.policeReconBlock);
    }
}
