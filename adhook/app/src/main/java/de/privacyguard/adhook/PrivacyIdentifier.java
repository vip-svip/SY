package de.privacyguard.adhook;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** Pure-Java derivation for an opt-in, stable, package-scoped Android ID replacement. */
public final class PrivacyIdentifier {
    private PrivacyIdentifier() {}

    /** Returns 16 lowercase hexadecimal characters, stable per package name. */
    public static String forPackage(String packageName) {
        String pkg = packageName == null ? "" : packageName;
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(("FX-ANDROID-ID-v1:" + pkg).getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder(16);
            for (int i = 0; i < 8; i++) out.append(String.format(Locale.ROOT, "%02x", digest[i] & 0xff));
            return out.toString();
        } catch (Throwable ignored) {
            // Defensive fallback; Android provides SHA-256, but never return a malformed value.
            return String.format(Locale.ROOT, "%016x", ((long) pkg.hashCode()) & 0xffffffffL);
        }
    }
}
