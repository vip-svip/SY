package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class PrivacyIdentifierTest {
    @Test
    public void advertisingIdentifierIsStablePackageScopedAndUuidShaped() {
        String first = PrivacyIdentifier.forAdvertisingId("com.example.app");
        assertEquals(first, PrivacyIdentifier.forAdvertisingId("com.example.app"));
        assertNotEquals(first, PrivacyIdentifier.forAdvertisingId("com.example.other"));
        assertTrue(first.matches("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}"));
        assertNull(PrivacyIdentifier.forAdvertisingId(null));
        assertNull(PrivacyIdentifier.forAdvertisingId(""));
    }

    @Test
    public void identifierIsStableForTheSamePackageAndDevice() {
        assertEquals(PrivacyIdentifier.forPackage("com.example.app", "device-id-1"),
                PrivacyIdentifier.forPackage("com.example.app", "device-id-1"));
    }

    @Test
    public void identifierIsScopedToPackageName() {
        assertNotEquals(PrivacyIdentifier.forPackage("com.example.app", "device-id-1"),
                PrivacyIdentifier.forPackage("com.example.other", "device-id-1"));
    }

    @Test
    public void identifierIsScopedToDeviceAndPackage() {
        assertNotEquals(PrivacyIdentifier.forPackage("com.example.app", "device-id-1"),
                PrivacyIdentifier.forPackage("com.example.app", "device-id-2"));
    }

    @Test
    public void nullOriginalIdentifierRemainsNull() {
        assertNull(PrivacyIdentifier.forPackage("com.example.app", null));
    }

    @Test
    public void emptyOriginalIdentifierRemainsEmpty() {
        assertEquals("", PrivacyIdentifier.forPackage("com.example.app", ""));
    }

    @Test
    public void missingPackageFailsOpenToOriginalIdentifier() {
        assertEquals("device-id-1", PrivacyIdentifier.forPackage(null, "device-id-1"));
        assertEquals("device-id-1", PrivacyIdentifier.forPackage("", "device-id-1"));
    }

    @Test
    public void nullPackageNameIsHandledDeterministically() {
        assertEquals(PrivacyIdentifier.forPackage("", "device-id-1"),
                PrivacyIdentifier.forPackage(null, "device-id-1"));
    }

    @Test
    public void identifierHasAndroidIdCompatibleHexShape() {
        assertTrue(PrivacyIdentifier.forPackage("com.example.app", "device-id-1").matches("[0-9a-f]{16}"));
    }
}
