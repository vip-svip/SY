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
    public static String forPackage(String packageName, String originalAndroidId) {
        if (originalAndroidId == null || originalAndroidId.isEmpty()) return originalAndroidId;
        String pkg = packageName == null ? "" : packageName;
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
