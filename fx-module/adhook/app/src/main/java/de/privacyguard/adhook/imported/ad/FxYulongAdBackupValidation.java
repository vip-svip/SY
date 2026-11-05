package de.privacyguard.adhook.imported.ad;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.Locale;

public final class FxYulongAdBackupValidation {
    private FxYulongAdBackupValidation() { }

    public static boolean isValidDomain(String raw) {
        if (raw == null || raw.isEmpty() || raw.length() > 253
                || !raw.equals(raw.trim()) || raw.startsWith(".")
                || raw.endsWith(".") || raw.contains("..")) return false;
        String[] labels = raw.toLowerCase(Locale.ROOT).split("\\.", -1);
        for (String label : labels) {
            if (label.isEmpty() || label.length() > 63
                    || !label.matches("[a-z0-9](?:[a-z0-9-]*[a-z0-9])?")) return false;
        }
        return true;
    }

    public static boolean isValidText(String value) {
        if (value == null || value.isEmpty()
                || value.getBytes(StandardCharsets.UTF_8).length > 180
                || value.indexOf('|') >= 0) return false;
        for (int i = 0; i < value.length(); i++) {
            char ch = value.charAt(i);
            if (ch == '\r' || ch == '\n' || ch == '\0'
                    || (ch < 0x20 && ch != '\t') || ch == 0x7f) return false;
        }
        return true;
    }

    public static boolean isValidSource(String value) {
        if (value == null || value.isEmpty()
                || value.getBytes(StandardCharsets.UTF_8).length > 2048) return false;
        return value.matches("https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+")
                || value.matches("builtin://[A-Za-z0-9._-]+");
    }

    public static boolean isValidIpv4(String value) {
        if (value == null || !value.matches("[0-9]{1,3}(?:\\.[0-9]{1,3}){3}")) return false;
        String[] parts = value.split("\\.", -1);
        for (String part : parts) if (Integer.parseInt(part) > 255) return false;
        return !"0.0.0.0".equals(value) && !"255.255.255.255".equals(value);
    }

    public static boolean isValidDnsEndpoint(String value, boolean ipv4Only) {
        if (isValidIpv4(value)) return true;
        if (ipv4Only || value == null || value.isEmpty() || value.length() > 2048) return false;
        for (int i = 0; i < value.length(); i++) {
            char ch = value.charAt(i);
            if (Character.isWhitespace(ch) || Character.isISOControl(ch) || ch == ',') return false;
        }
        try {
            URI uri = new URI(value);
            String scheme = uri.getScheme();
            if (scheme == null || uri.getRawUserInfo() != null || uri.getHost() == null) return false;
            String normalizedScheme = scheme.toLowerCase(Locale.ROOT);
            if (!"https".equals(normalizedScheme) && !"tls".equals(normalizedScheme)
                    && !"quic".equals(normalizedScheme)) return false;
            if (!isValidDomain(uri.getHost()) && !isValidIpv4(uri.getHost())) return false;
            int port = uri.getPort();
            if (port == 0 || port > 65535) return false;
            if (!"https".equals(normalizedScheme)) {
                return (uri.getRawPath() == null || uri.getRawPath().isEmpty())
                        && uri.getRawQuery() == null && uri.getRawFragment() == null;
            }
            return uri.getRawPath() == null || uri.getRawPath().isEmpty()
                    || uri.getRawPath().matches("/[A-Za-z0-9._~!$&()*+,;=:@%/?#-]*");
        } catch (Exception invalid) {
            return false;
        }
    }
}
