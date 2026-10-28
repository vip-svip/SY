package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class PrivacyIdentifierTest {
    @Test
    public void identifierIsStableForTheSamePackage() {
        assertEquals(PrivacyIdentifier.forPackage("com.example.app"),
                PrivacyIdentifier.forPackage("com.example.app"));
    }

    @Test
    public void identifierIsScopedToPackageName() {
        assertNotEquals(PrivacyIdentifier.forPackage("com.example.app"),
                PrivacyIdentifier.forPackage("com.example.other"));
    }

    @Test
    public void identifierHasAndroidIdCompatibleHexShape() {
        assertTrue(PrivacyIdentifier.forPackage("com.example.app").matches("[0-9a-f]{16}"));
    }
}
