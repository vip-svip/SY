package de.privacyguard.adhook;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;

/** App-scoped Advertising ID isolation policy. No account, purchase or server state is modified. */
public final class AdvertisingIdPrivacyPolicy {
    private AdvertisingIdPrivacyPolicy() {}

    public static boolean shouldUnify(boolean privacyEnabled, int processPackageCount,
                                      String packageName, UnifiedHookConfigParser.Target target) {
        return privacyEnabled && processPackageCount == 1 && packageName != null && !packageName.isEmpty()
                && target != null && target.adIdUnify
                && !"android".equals(packageName) && !"system".equals(packageName)
                && !"de.privacyguard.hook".equals(packageName)
                && !"de.privacyguard.adhook".equals(packageName)
                && !"org.lsposed.manager".equals(packageName);
    }

    /** Deterministic UUID-shaped ID isolated by package; never logs or reads a real account ID. */
    public static String syntheticId(String packageName) {
        if (packageName == null || packageName.isEmpty()) return null;
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(("FX-AD-ID-v1:" + packageName).getBytes(StandardCharsets.UTF_8));
            digest[6] = (byte) ((digest[6] & 0x0f) | 0x40);
            digest[8] = (byte) ((digest[8] & 0x3f) | 0x80);
            StringBuilder out = new StringBuilder(36);
            for (int i = 0; i < 16; i++) {
                if (i == 4 || i == 6 || i == 8 || i == 10) out.append('-');
                out.append(String.format(Locale.ROOT, "%02x", digest[i] & 0xff));
            }
            return out.toString();
        } catch (Exception ignored) {
            return null;
        }
    }
}
