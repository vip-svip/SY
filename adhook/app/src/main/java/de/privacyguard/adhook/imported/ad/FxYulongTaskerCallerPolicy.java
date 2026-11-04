package de.privacyguard.adhook.imported.ad;

/** Fail-closed identity check for Root-backed Tasker broadcasts. */
public final class FxYulongTaskerCallerPolicy {
    public static final int MIN_VERIFIABLE_API = 34;

    private FxYulongTaskerCallerPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_-]+)+")
                && !value.contains("..")
                && !"de.privacyguard.adhook".equals(value);
    }

    /**
     * API 34 exposes the actual originating package/UID for a delivered broadcast.
     * In addition, the sender's current APK signer set must match the fingerprint
     * explicitly saved by the user. Package-name reuse after uninstall/reinstall
     * therefore does not inherit the previous app's Root automation authorization.
     */
    public static boolean isAuthorized(int sdkInt, String senderPackage, int senderUid,
                                       String configuredPackage, String[] packagesForUid,
                                       String configuredSignerDigests, String senderSignerDigests) {
        if (sdkInt < MIN_VERIFIABLE_API || senderUid < 0
                || !isValidPackageName(configuredPackage)
                || !configuredPackage.equals(senderPackage)
                || packagesForUid == null || packagesForUid.length == 0
                || !matchesSignerDigestSet(configuredSignerDigests, senderSignerDigests)) {
            return false;
        }
        for (String packageName : packagesForUid) {
            if (configuredPackage.equals(packageName)) return true;
        }
        return false;
    }

    /** Compare canonical SHA-256 signer sets without depending on certificate order. */
    public static boolean matchesSignerDigestSet(String expected, String actual) {
        java.util.SortedSet<String> expectedSet = parseSignerDigestSet(expected);
        java.util.SortedSet<String> actualSet = parseSignerDigestSet(actual);
        return expectedSet != null && actualSet != null
                && !expectedSet.isEmpty() && expectedSet.equals(actualSet);
    }

    private static java.util.SortedSet<String> parseSignerDigestSet(String raw) {
        if (raw == null || raw.isEmpty() || raw.length() > 8 * 65 - 1) return null;
        String[] values = raw.split(",", -1);
        if (values.length == 0 || values.length > 8) return null;
        java.util.SortedSet<String> normalized = new java.util.TreeSet<>();
        for (String value : values) {
            if (value == null || !value.matches("(?i)[0-9a-f]{64}")) return null;
            if (!normalized.add(value.toLowerCase(java.util.Locale.ROOT))) return null;
        }
        return normalized;
    }
}
