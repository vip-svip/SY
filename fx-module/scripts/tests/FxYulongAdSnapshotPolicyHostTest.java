package de.privacyguard.adhook.imported.ad;

/** Standalone JDK tests for fail-closed parsing of the Ad control snapshot. */
public final class FxYulongAdSnapshotPolicyHostTest {
    private static int assertions;

    private static void check(Boolean expected, Boolean actual, String label) {
        assertions++;
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(label + ": expected=" + expected + " actual=" + actual);
        }
    }

    public static void main(String[] args) {
        check(Boolean.TRUE, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nAD_MASTER|1\nRULE|builtin://ads|Ads|1\n"), "enabled master");
        check(Boolean.FALSE, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nAD_MASTER|0\n"), "disabled master");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(null), "null snapshot");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(""), "empty snapshot");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled("AD_MASTER|1\n"), "missing header");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nRULE|builtin://ads|Ads|1\n"), "missing master record");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nAD_MASTER|yes\n"), "non-binary master");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nAD_MASTER|\n"), "empty master value");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nAD_MASTER|1|extra\n"), "extra master fields");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nAD_MASTER|1\nAD_MASTER|0\n"), "duplicate master record");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "FXYULONGAD1\nFXYULONGAD1\nAD_MASTER|1\n"), "duplicate header");
        check(null, FxYulongAdSnapshotPolicy.parseAdMasterEnabled(
                "unexpected\nFXYULONGAD1\nAD_MASTER|1\n"), "leading protocol noise");
        System.out.println("PASS: " + assertions + " Yulong Ad snapshot policy assertions");
    }
}
