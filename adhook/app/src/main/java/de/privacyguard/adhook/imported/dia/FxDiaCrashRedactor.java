package de.privacyguard.adhook.imported.dia;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Redacts common credentials from crash-report exports.
 *
 * The private on-device record remains unchanged for diagnosis. Only explicit
 * copy/share payloads pass through this class.
 */
public final class FxDiaCrashRedactor {
    private static final String SENSITIVE_KEYS =
            "(?:access[_-]?token|refresh[_-]?token|id[_-]?token|token|client[_-]?secret|" +
            "app[_-]?secret|private[_-]?key|signing[_-]?key|access[_-]?key(?:[_-]?id)?|" +
            "aws[_-]?secret[_-]?access[_-]?key|api[_-]?key|password|passwd|secret|" +
            "cookie|set-cookie|session[_-]?(?:id|key))";
    private static final Pattern HEADER = Pattern.compile(
            "(?im)(\\b(?:authorization|proxy-authorization)\\s*[:=]\\s*)[^\\r\\n]+");
    private static final Pattern KEY_VALUE = Pattern.compile(
            "(?i)(\\b" + SENSITIVE_KEYS + "\\b[\"']?\\s*[:=]\\s*)(\"[^\"]*\"|'[^']*'|[^\\s,;&}\\]]+)");
    private static final Pattern QUERY_VALUE = Pattern.compile(
            "(?i)([?&]" + SENSITIVE_KEYS + "=)[^&#\\s]+");
    private static final Pattern URL_USER_INFO = Pattern.compile(
            "(?i)([a-z][a-z0-9+.-]*://)[^/@\\s:]+(?::[^/@\\s]*)?@");
    private static final Pattern BEARER = Pattern.compile(
            "(?i)\\bBearer\\s+[A-Za-z0-9._~+/-]+=*");
    private static final Pattern JWT = Pattern.compile(
            "\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\b");
    private static final Pattern PEM_PRIVATE_KEY = Pattern.compile(
            "(?s)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----");

    private FxDiaCrashRedactor() { }

    public static String redact(String value) {
        if (value == null || value.isEmpty()) return "";
        String result = HEADER.matcher(value).replaceAll("$1[REDACTED]");
        result = replaceKeyValues(result);
        result = QUERY_VALUE.matcher(result).replaceAll("$1[REDACTED]");
        result = URL_USER_INFO.matcher(result).replaceAll("$1[REDACTED]@");
        result = BEARER.matcher(result).replaceAll("Bearer [REDACTED]");
        result = JWT.matcher(result).replaceAll("[REDACTED_JWT]");
        result = PEM_PRIVATE_KEY.matcher(result).replaceAll("[REDACTED_PRIVATE_KEY]");
        return result;
    }

    private static String replaceKeyValues(String input) {
        Matcher matcher = KEY_VALUE.matcher(input);
        StringBuffer out = new StringBuffer(input.length());
        while (matcher.find()) {
            String value = matcher.group(2);
            String replacement = matcher.group(1)
                    + (value.startsWith("\"") ? "\"[REDACTED]\""
                    : value.startsWith("'") ? "'[REDACTED]'" : "[REDACTED]");
            matcher.appendReplacement(out, Matcher.quoteReplacement(replacement));
        }
        matcher.appendTail(out);
        return out.toString();
    }
}
