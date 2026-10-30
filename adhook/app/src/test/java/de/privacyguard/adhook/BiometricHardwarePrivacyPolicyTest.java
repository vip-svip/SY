package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class BiometricHardwarePrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.bio," + flags + "\n").targets.get("com.example.bio");
    }

    @Test public void fingerprintAndFaceFlagsAreIndependent() {
        UnifiedHookConfigParser.Target fingerprint = target("hide_fingerprint_hw=1");
        assertTrue(BiometricHardwarePrivacyPolicy.shouldHideFingerprint(true, 1, "com.example.bio", fingerprint));
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 1, "com.example.bio", fingerprint));
        UnifiedHookConfigParser.Target face = target("hide_face_hw=1");
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFingerprint(true, 1, "com.example.bio", face));
        assertTrue(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 1, "com.example.bio", face));
    }

    @Test public void sharedProcessesAndMasterOffFailOpen() {
        UnifiedHookConfigParser.Target both = target("hide_fingerprint_hw=1,hide_face_hw=1");
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFingerprint(false, 1, "com.example.bio", both));
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 2, "com.example.bio", both));
    }

    @Test public void protectedAndUnknownPackagesFailOpen() {
        UnifiedHookConfigParser.Target both = target("hide_fingerprint_hw=1,hide_face_hw=1");
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFingerprint(true, 1, "android", both));
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 1, "de.privacyguard.adhook", both));
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 1, "org.lsposed.manager", both));
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 1, null, both));
        assertFalse(BiometricHardwarePrivacyPolicy.shouldHideFace(true, 1, "com.example.bio", null));
    }
}
