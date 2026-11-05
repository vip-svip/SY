package de.privacyguard.adhook.imported.dia;

import java.net.URI;

/** Strict host policy for authenticated GitHub raw-backup downloads. */
public final class FxDiaGithubBackupPolicy {
    private FxDiaGithubBackupPolicy() { }

    public static boolean isTrustedDownloadUrl(String value) {
        if (value == null || value.length() > 4096) return false;
        try {
            URI uri = new URI(value);
            String scheme = uri.getScheme();
            String host = uri.getHost();
            int port = uri.getPort();
            return "https".equalsIgnoreCase(scheme)
                    && "raw.githubusercontent.com".equalsIgnoreCase(host)
                    && uri.getRawUserInfo() == null
                    && (port == -1 || port == 443)
                    && uri.getRawFragment() == null
                    && uri.getRawPath() != null
                    && uri.getRawPath().startsWith("/");
        } catch (Exception invalid) {
            return false;
        }
    }
}
