package de.privacyguard.adhook;

import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Conservative importer for Surge/Loon [Script] and Quantumult X [rewrite_local].
 * Only HTTPS HTTP request/response script actions are migrated. Ordinary rewrite,
 * reject, cron, task and local-path entries are deliberately not executable scripts.
 */
public final class NativeScriptModuleImporter {
    private static final Pattern OPTION = Pattern.compile(
            "(?:^|,)\\s*([A-Za-z0-9_-]+)\\s*=\\s*(.*?)(?=,\\s*[A-Za-z0-9_-]+\\s*=|$)",
            Pattern.CASE_INSENSITIVE);

    private NativeScriptModuleImporter() { }

    public static JSONObject parse(String payload) throws JSONException {
        JSONArray entries = new JSONArray();
        Set<String> seen = new HashSet<>();
        boolean inScript = false;
        boolean inRewriteLocal = false;

        String[] lines = (payload == null ? "" : payload).split("\\r?\\n");
        for (String rawLine : lines) {
            String line = rawLine.trim();
            if (line.isEmpty() || line.startsWith("#") || line.startsWith(";")) continue;
            if (line.startsWith("[") && line.endsWith("]")) {
                String section = line.substring(1, line.length() - 1).trim();
                inScript = "script".equalsIgnoreCase(section);
                inRewriteLocal = "rewrite_local".equalsIgnoreCase(section);
                continue;
            }
            if (!inScript && !inRewriteLocal) continue;

            String name;
            String scriptUrl;
            String pattern;
            boolean request = false;
            boolean response = false;
            boolean bodyRequired = false;
            String requiresBody = "";

            if (inScript) {
                int equals = line.indexOf('=');
                if (equals <= 0) continue;
                name = line.substring(0, equals).trim();
                String options = line.substring(equals + 1).trim();
                scriptUrl = option(options, "script-path");
                String type = option(options, "type").toLowerCase(Locale.ROOT);
                pattern = option(options, "pattern");
                requiresBody = option(options, "requires-body").toLowerCase(Locale.ROOT);
                for (String trigger : type.replaceAll("\\s+", "").split("[,;]")) {
                    if ("http-request".equals(trigger)) request = true;
                    else if ("http-response".equals(trigger)) response = true;
                }
                if (!requiresBody.isEmpty() && !"0".equals(requiresBody)
                        && !"1".equals(requiresBody) && !"true".equals(requiresBody)
                        && !"false".equals(requiresBody)) continue;
                bodyRequired = "1".equals(requiresBody) || "true".equals(requiresBody);
            } else {
                String lower = line.toLowerCase(Locale.ROOT);
                int urlMarker = lower.indexOf(" url ");
                if (urlMarker <= 0) continue;
                pattern = line.substring(0, urlMarker).trim();
                String[] ruleParts = line.substring(urlMarker + 5).trim().split("\\s+");
                if (ruleParts.length < 2) continue;
                String action = ruleParts[0].toLowerCase(Locale.ROOT);
                scriptUrl = ruleParts[1];
                if (scriptUrl.regionMatches(true, 0, "script-path=", 0, 12)) {
                    scriptUrl = scriptUrl.substring(12);
                }
                switch (action) {
                    case "script-request-header":
                        request = true;
                        break;
                    case "script-request-body":
                        request = true;
                        bodyRequired = true;
                        break;
                    case "script-response-header":
                        response = true;
                        break;
                    case "script-response-body":
                    case "script-analyze-echo-response":
                        response = true;
                        bodyRequired = true;
                        break;
                    default:
                        continue;
                }
                name = "Quantumult X " + action;
                for (int i = 2; i < ruleParts.length; i++) {
                    if (ruleParts[i].regionMatches(true, 0, "tag=", 0, 4)) {
                        name = ruleParts[i].substring(4);
                        break;
                    }
                }
            }

            if (!request && !response) continue;
            if (scriptUrl == null || !scriptUrl.regionMatches(true, 0, "https://", 0, 8)) continue;
            URI uri;
            try {
                uri = new URI(scriptUrl);
            } catch (URISyntaxException malformed) {
                continue;
            }
            if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                    || uri.getRawUserInfo() != null || uri.getPort() == 0 || uri.getPort() > 65535) continue;
            if (pattern == null || pattern.isEmpty() || !pattern.matches("(?is).*https?://.*")) continue;
            if (name == null || name.trim().isEmpty()) continue;

            String type = request && response ? "both" : request ? "request" : "response";
            String safeName = name.replaceAll("[\\p{Cntrl}]", " ").trim();
            if (safeName.isEmpty()) continue;
            String bodyFlag = bodyRequired ? "1" : "0";
            String metadata = type + "\n" + pattern + "\n" + bodyFlag + "\n" + safeName;
            String duplicateKey = scriptUrl + "\n" + metadata;
            if (!seen.add(duplicateKey)) continue;

            JSONObject entry = new JSONObject();
            entry.put("value", scriptUrl);
            entry.put("name", "FXMETA_B64:" + Base64.encodeToString(
                    metadata.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP));
            entry.put("enabled", true);
            entries.put(entry);
        }

        if (entries.length() == 0) {
            throw new IllegalArgumentException(
                    "未找到可迁移的 HTTPS [Script] 或 Quantumult X [rewrite_local] 请求/响应脚本；普通 URL Rewrite、任务脚本、定时脚本和本地相对路径不会自动执行");
        }
        JSONObject document = new JSONObject();
        document.put("format", "FX-SCRIPT-LIST");
        document.put("version", 1);
        document.put("scripts", entries);
        return document;
    }

    private static String option(String options, String key) {
        if (options == null || key == null) return "";
        Matcher matcher = OPTION.matcher(options);
        while (matcher.find()) {
            if (key.equalsIgnoreCase(matcher.group(1))) return unquote(matcher.group(2));
        }
        return "";
    }

    private static String unquote(String raw) {
        if (raw == null) return "";
        String value = raw.trim();
        if (value.length() >= 2 && value.charAt(0) == '"'
                && value.charAt(value.length() - 1) == '"') {
            return value.substring(1, value.length() - 1);
        }
        if (value.length() >= 2 && value.charAt(0) == '\''
                && value.charAt(value.length() - 1) == '\'') {
            return value.substring(1, value.length() - 1).replace("''", "'");
        }
        return value;
    }
}
