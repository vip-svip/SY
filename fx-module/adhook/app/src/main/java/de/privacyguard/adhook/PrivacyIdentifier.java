package de.privacyguard.adhook;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** Pure-Java derivation for an opt-in, stable, package-scoped Android ID replacement. */
public final class PrivacyIdentifier {
    private PrivacyIdentifier() {}

    /**
     * Returns a deterministic 16-hex identifier scoped to this package and the device's
     * original ID. If a cryptographic digest cannot be created, preserve the original
     * value instead of silently substituting a weaker, collision-prone hash.
     */
    /**
     * Deterministic RFC-4122-shaped advertising identifier shared by Google/Huawei
     * String-returning APIs inside one selected app. It is package-scoped, not device-wide.
     * A missing package or digest provider fails open (null means keep the platform value).
     */
    public static String forAdvertisingId(String packageName) {
        if (packageName == null || packageName.isEmpty()) return null;
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(("FX-AD-ID-v1:" + packageName).getBytes(StandardCharsets.UTF_8));
            byte[] uuid = java.util.Arrays.copyOf(digest, 16);
            uuid[6] = (byte) ((uuid[6] & 0x0f) | 0x50);
            uuid[8] = (byte) ((uuid[8] & 0x3f) | 0x80);
            StringBuilder hex = new StringBuilder(32);
            for (byte value : uuid) hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
            return hex.substring(0, 8) + "-" + hex.substring(8, 12) + "-"
                    + hex.substring(12, 16) + "-" + hex.substring(16, 20) + "-"
                    + hex.substring(20, 32);
        } catch (Exception ignored) {
            return null;
        }
    }

    public static String forPackage(String packageName, String originalAndroidId) {
        if (originalAndroidId == null || originalAndroidId.isEmpty()) return originalAndroidId;
        // Fail open if package scoping is unavailable; never emit one shared synthetic ID.
        if (packageName == null || packageName.isEmpty()) return originalAndroidId;
        String pkg = packageName;
        String input = "FX-ANDROID-ID-v1:" + pkg + ":" + originalAndroidId;
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(16);
            for (int i = 0; i < 8; i++) {
                out.append(String.format(Locale.ROOT, "%02x", digest[i] & 0xff));
            }
            return out.toString();
        } catch (Exception ignored) {
            // Fail open to the platform value: do not manufacture a weaker identifier.
            return originalAndroidId;
        }
    }
}
