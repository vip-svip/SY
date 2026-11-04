package de.privacyguard.adhook.imported.ad;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class FxYulongTaskerCallerPolicyTest {
    private static final String AUTOMATION = "com.example.automation";
    private static final String SIGNER_A =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private static final String SIGNER_B =
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    @Test public void acceptsConfiguredPackageUidAndSigner() {
        assertTrue(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION,
                new String[]{AUTOMATION}, SIGNER_A, SIGNER_A));
    }

    @Test public void rejectsAndroidVersionsWithoutPublicSenderIdentity() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                33, AUTOMATION, 10234, AUTOMATION,
                new String[]{AUTOMATION}, SIGNER_A, SIGNER_A));
    }

    @Test public void rejectsDifferentSenderEvenWhenUidMapsToBothPackages() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, "com.example.other", 10234, AUTOMATION,
                new String[]{AUTOMATION, "com.example.other"}, SIGNER_A, SIGNER_A));
    }

    @Test public void rejectsSenderNotMappedToReportedUid() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION,
                new String[]{"com.example.other"}, SIGNER_A, SIGNER_A));
    }

    @Test public void rejectsChangedOrMissingSigner() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION,
                new String[]{AUTOMATION}, SIGNER_A, SIGNER_B));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION,
                new String[]{AUTOMATION}, SIGNER_A, ""));
    }

    @Test public void rejectsMissingOrInvalidIdentity() {
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, null, -1, AUTOMATION, new String[]{AUTOMATION}, SIGNER_A, SIGNER_A));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, "", new String[]{AUTOMATION}, SIGNER_A, SIGNER_A));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, "de.privacyguard.adhook",
                new String[]{AUTOMATION}, SIGNER_A, SIGNER_A));
        assertFalse(FxYulongTaskerCallerPolicy.isAuthorized(
                34, AUTOMATION, 10234, AUTOMATION, null, SIGNER_A, SIGNER_A));
    }

    @Test public void signerDigestIsStableAcrossSignerOrdering() {
        String first = FxYulongTaskerCallerPolicy.signerDigest(
                new byte[][]{{1, 2, 3}, {4, 5, 6}});
        String second = FxYulongTaskerCallerPolicy.signerDigest(
                new byte[][]{{4, 5, 6}, {1, 2, 3}});
        assertEquals(first, second);
        assertEquals(129, first.length());
        assertFalse(FxYulongTaskerCallerPolicy.signerDigest(null).length() > 0);
    }
}
