package de.privacyguard.adhook.imported.ad;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Fail-closed identity check for Root-backed Tasker broadcasts. */
public final class FxYulongTaskerCallerPolicy {
    public static final int MIN_VERIFIABLE_API = 34;

    private FxYulongTaskerCallerPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)+")
                && !value.contains("..")
                && !"de.privacyguard.adhook".equals(value);
    }

    public static boolean isAuthorized(int sdkInt, String senderPackage, int senderUid,
                                       String configuredPackage, String[] packagesForUid,
                                       String configuredSignerDigest, String senderSignerDigest) {
        if (sdkInt < MIN_VERIFIABLE_API || senderUid < 0
                || !isValidPackageName(configuredPackage)
                || !configuredPackage.equals(senderPackage)
                || !isValidSignerDigest(configuredSignerDigest)
                || !isValidSignerDigest(senderSignerDigest)
                || !MessageDigest.isEqual(
                        configuredSignerDigest.getBytes(StandardCharsets.US_ASCII),
                        senderSignerDigest.getBytes(StandardCharsets.US_ASCII))
                || packagesForUid == null || packagesForUid.length == 0) {
            return false;
        }
        for (String packageName : packagesForUid) {
            if (configuredPackage.equals(packageName)) return true;
        }
        return false;
    }

    /** Stable SHA-256 pin for every current APK signer, sorted before joining. */
    public static String signerDigest(byte[][] signerCertificates) {
        if (signerCertificates == null || signerCertificates.length == 0) return "";
        try {
            List<String> digests = new ArrayList<>();
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            for (byte[] certificate : signerCertificates) {
                if (certificate == null || certificate.length == 0) return "";
                byte[] digest = sha256.digest(certificate);
                StringBuilder hex = new StringBuilder(64);
                for (byte value : digest) {
                    hex.append(String.format(java.util.Locale.ROOT, "%02x", value & 0xff));
                }
                digests.add(hex.toString());
            }
            Collections.sort(digests);
            StringBuilder joined = new StringBuilder();
            for (String digest : digests) {
                if (joined.length() > 0) joined.append(',');
                joined.append(digest);
            }
            return joined.toString();
        } catch (java.security.NoSuchAlgorithmException impossible) {
            return "";
        }
    }

    private static boolean isValidSignerDigest(String value) {
        if (value == null || value.isEmpty() || value.length() > 1024) return false;
        String[] parts = value.split(",", -1);
        if (parts.length == 0 || parts.length > 16) return false;
        for (String part : parts) if (!part.matches("[0-9a-f]{64}")) return false;
        return true;
    }
}
