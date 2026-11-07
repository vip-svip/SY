package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class BiometricPrivacyPolicyTest {
    private UnifiedHookConfigParser.Target target(String flags) {
        return UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n"
                        + "com.example.bio," + flags + "\n").targets.get("com.example.bio");
    }

    @Test public void fingerprintAndFaceFlagsAreIndependent() {
        UnifiedHookConfigParser.Target t = target("hide_fingerprint_hw=1,hide_face_hw=0");
        assertTrue(BiometricPrivacyPolicy.shouldHideFingerprint(true, 1, "com.example.bio", t));
        assertFalse(BiometricPrivacyPolicy.shouldHideFace(true, 1, "com.example.bio", t));
        assertFalse(BiometricPrivacyPolicy.shouldReportNoBiometricHardware(true, 1, "com.example.bio", t));
        UnifiedHookConfigParser.Target both = target("hide_fingerprint_hw=1,hide_face_hw=1");
        assertTrue(BiometricPrivacyPolicy.shouldReportNoBiometricHardware(true, 1, "com.example.bio", both));
    }

    @Test public void biometricHidingRequiresMasterAndSinglePackage() {
        UnifiedHookConfigParser.Target t = target("hide_fingerprint_hw=1,hide_face_hw=1");
        assertFalse(BiometricPrivacyPolicy.shouldHideFingerprint(false, 1, "com.example.bio", t));
        assertFalse(BiometricPrivacyPolicy.shouldHideFace(true, 2, "com.example.bio", t));
        assertFalse(BiometricPrivacyPolicy.shouldReportNoBiometricHardware(true, 2, "com.example.bio", t));
    }

    @Test public void protectedAndUnknownPackagesFailOpen() {
        UnifiedHookConfigParser.Target t = target("hide_fingerprint_hw=1,hide_face_hw=1");
        assertFalse(BiometricPrivacyPolicy.shouldHideFingerprint(true, 1, "android", t));
        assertFalse(BiometricPrivacyPolicy.shouldHideFace(true, 1, "de.privacyguard.adhook", t));
        assertFalse(BiometricPrivacyPolicy.shouldHideFace(true, 1, "org.lsposed.manager", t));
        assertFalse(BiometricPrivacyPolicy.shouldHideFingerprint(true, 1, null, t));
    }
}
