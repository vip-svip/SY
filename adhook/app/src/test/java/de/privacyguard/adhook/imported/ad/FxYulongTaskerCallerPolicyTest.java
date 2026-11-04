package de.privacyguard.adhook.imported.ad;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class FxYulongTaskerCallerPolicyTest {
    private static final String AUTOMATION = "com.example.automation";

    @Test public void acceptsConfiguredPackageWhenUidMapsToSender() {
        assertTrue(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION,
                new String[]{AUTOMATION}));
    }

    @Test public void rejectsAndroidVersionsWithoutPublicSenderIdentity() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                33, AUTOMATION, 10234, AUTOMATION,
                new String[]{AUTOMATION}));
    }

    @Test public void rejectsDifferentSenderEvenWhenUidMapsToBothPackages() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, "com.example.other", 10234, AUTOMATION,
                new String[]{AUTOMATION, "com.example.other"}));
    }

    @Test public void rejectsSenderNotMappedToReportedUid() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION,
                new String[]{"com.example.other"}));
    }

    @Test public void rejectsMissingOrInvalidIdentity() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, null, -1, AUTOMATION, new String[]{AUTOMATION}));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, "", new String[]{AUTOMATION}));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, "de.privacyguard.adhook", new String[]{AUTOMATION}));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION, null));
    }
}
