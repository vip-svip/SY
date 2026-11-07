package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class CameraPrivacyPolicyTest {
    @Test public void cameraIdEnumerationIsOptInAndSinglePackageOnly() {
        UnifiedHookConfigParser.Target target = UnifiedHookConfigParser.parse(
                "schema_version=1\nads_enabled=0\nprivacy_enabled=1\n[list:targets]\n" +
                "com.example.camera,camera_id_hide=1\n").targets.get("com.example.camera");
        assertTrue(CameraPrivacyPolicy.shouldHideCameraIds(true, 1, "com.example.camera", target));
        assertFalse(CameraPrivacyPolicy.shouldHideCameraIds(false, 1, "com.example.camera", target));
        assertFalse(CameraPrivacyPolicy.shouldHideCameraIds(true, 2, "com.example.camera", target));
        assertFalse(CameraPrivacyPolicy.shouldHideCameraIds(true, 1, "android", target));
        assertFalse(CameraPrivacyPolicy.shouldHideCameraIds(true, 1, "de.privacyguard.adhook", target));
    }
}
