package de.privacyguard.adhook;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** Pure-Java derivation for an opt-in, stable, package-scoped Android ID replacement. */
public final class PrivacyIdentifier {
    private PrivacyIdentifier() {}

    /**
     * Returns a deterministic 16-hex identifier unique to this package and device's original ID.
     * Different devices do not receive the same replacement merely because they run the same app.
     */
    public static String forPackage(String packageName, String originalAndroidId) {
        if (originalAndroidId == null || originalAndroidId.isEmpty()) return originalAndroidId;
        String pkg = packageName == null ? "" : packageName;
        String input = "FX-ANDROID-ID-v1:" + pkg + ":" + originalAndroidId;
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(16);
            for (int i = 0; i < 8; i++) out.append(String.format(Locale.ROOT, "%02x", digest[i] & 0xff));
            return out.toString();
        } catch (Throwable ignored) {
            // Defensive fallback retains both inputs; Android provides SHA-256.
            return String.format(Locale.ROOT, "%016x", ((long) (pkg + ":" + originalAndroidId).hashCode()) & 0xffffffffL);
        }
    }
}
