package de.privacyguard.adhook;

import android.net.Uri;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Conservative Egern scriptings YAML importer.
 *
 * Only remote HTTPS HTTP request/response entries that map to FX's current
 * URL-triggered hook metadata are emitted. Scheduling, network callbacks,
 * environment injection and binary-body records are not converted into
 * misleading or partially working hooks. Text body-required metadata is retained.
 */
public final class EgernScriptYamlImporter {
    private static final Pattern ITEM = Pattern.compile(
            "^-\\s*(http_request|http_response|schedule|generic|network)\\s*:\\s*$");

    private EgernScriptYamlImporter() {}

    public static JSONObject parse(String source) throws JSONException {
        JSONArray scripts = new JSONArray();
        Set<String> seen = new HashSet<>();
        boolean inScriptings = false;
        String kind = "";
        String name = "";
        String match = "";
        String scriptUrl = "";
        boolean disabled = false;
        boolean bodyRequired = false;
        boolean binaryBody = false;
        boolean hasEnvironment = false;
        boolean invalidEnvironment = false;
        int environmentIndent = -1;
        JSONObject scriptEnvironment = new JSONObject();

        String[] lines = (source == null ? "" : source).split("\\r?\\n");
        for (String sourceLine : lines) {
            String lineWithoutComment = stripComment(sourceLine);
            if (lineWithoutComment.trim().isEmpty()) continue;

            int indent = indentation(lineWithoutComment);
            String line = lineWithoutComment.trim();
            if (indent == 0) {
                if ("scriptings:".equalsIgnoreCase(line)) {
                    inScriptings = true;
                    continue;
                }
                if (inScriptings) {
                    addEntry(scripts, seen, kind, name, match, scriptUrl,
                            disabled, bodyRequired, binaryBody, hasEnvironment,
                            invalidEnvironment, scriptEnvironment);
                    kind = "";
                    inScriptings = false;
                }
                continue;
            }
            if (!inScriptings) continue;

            Matcher item = ITEM.matcher(line);
            if (item.matches()) {
                addEntry(scripts, seen, kind, name, match, scriptUrl,
                        disabled, bodyRequired, binaryBody, hasEnvironment,
                        invalidEnvironment, scriptEnvironment);
                kind = item.group(1);
                name = "";
                match = "";
                scriptUrl = "";
                disabled = false;
                bodyRequired = false;
                binaryBody = false;
                hasEnvironment = false;
                invalidEnvironment = false;
                environmentIndent = -1;
                scriptEnvironment = new JSONObject();
                continue;
            }
            if (kind.isEmpty()) continue;

            if (environmentIndent >= 0) {
                if (indent > environmentIndent) {
                    int envColon = line.indexOf(':');
                    if (envColon <= 0) {
                        invalidEnvironment = true;
                        continue;
                    }
                    String envKey = line.substring(0, envColon).trim();
                    String rawEnvValue = line.substring(envColon + 1).trim();
                    if (!envKey.matches("[A-Za-z_][A-Za-z0-9_.-]{0,63}")
                            || rawEnvValue.isEmpty()
                            || rawEnvValue.startsWith("{") || rawEnvValue.startsWith("[")
                            || rawEnvValue.startsWith("|") || rawEnvValue.startsWith(">")) {
                        invalidEnvironment = true;
                        continue;
                    }
                    String envValue = scalar(rawEnvValue);
                    if (envValue.length() > 512
                            || (!scriptEnvironment.has(envKey) && scriptEnvironment.length() >= 32)) {
                        invalidEnvironment = true;
                        continue;
                    }
                    scriptEnvironment.put(envKey, envValue);
                    if (scriptEnvironment.toString().length() > 2048) invalidEnvironment = true;
                    continue;
                }
                environmentIndent = -1;
            }

            int colon = line.indexOf(':');
            if (colon <= 0) continue;
            String key = line.substring(0, colon).trim().toLowerCase(Locale.ROOT);
            String value = scalar(line.substring(colon + 1));
            switch (key) {
                case "name": name = value; break;
                case "match": match = value; break;
                case "script_url": scriptUrl = value; break;
                case "disabled": disabled = truthy(value); break;
                case "body_required": bodyRequired = truthy(value); break;
                case "binary_body": binaryBody = truthy(value); break;
                case "env":
                    String rawEnvironment = line.substring(colon + 1).trim();
                    if (rawEnvironment.isEmpty()) {
                        environmentIndent = indent;
                    } else if (!"{}".equals(rawEnvironment)
                            && !"null".equalsIgnoreCase(rawEnvironment) && !"~".equals(rawEnvironment)) {
                        invalidEnvironment = true;
                    }
                    break;
                default: break;
            }
        }

        addEntry(scripts, seen, kind, name, match, scriptUrl,
                disabled, bodyRequired, binaryBody, hasEnvironment,
                invalidEnvironment, scriptEnvironment);
        if (scripts.length() == 0) {
            throw new IllegalArgumentException(
                    "没有可安全迁移的 Egern HTTPS HTTP 脚本；定时/通用/网络脚本，以及含 env 或 binary_body 的条目暂不导入");
        }

        JSONObject document = new JSONObject();
        document.put("format", "FX-SCRIPT-LIST");
        document.put("version", 1);
        document.put("scripts", scripts);
        return document;
    }

    private static void addEntry(JSONArray scripts, Set<String> seen,
                                 String kind, String name, String match, String scriptUrl,
                                 boolean disabled, boolean bodyRequired,
                                 boolean binaryBody, boolean hasEnvironment,
                                 boolean invalidEnvironment, JSONObject scriptEnvironment) throws JSONException {
        if (!"http_request".equals(kind) && !"http_response".equals(kind)) return;
        if (name == null || name.trim().isEmpty() || name.trim().length() > 512
                || match == null || match.isEmpty() || match.length() > 2048
                || scriptUrl == null || !scriptUrl.regionMatches(true, 0, "https://", 0, 8)) return;
        if (binaryBody || invalidEnvironment) return;

        Uri uri = Uri.parse(scriptUrl);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getPort() > 65535) return;

        String type = "http_request".equals(kind) ? "request" : "response";
        String safeName = name.trim().replaceAll("[\\p{Cntrl}]", " ");
        if (safeName.isEmpty() || safeName.length() > 512) return;
        String envJson = scriptEnvironment == null || scriptEnvironment.length() == 0
                ? "" : scriptEnvironment.toString();
        String metadata = type + "\n" + match + "\n" + (bodyRequired ? "1" : "0")
                + "\n" + safeName + (envJson.isEmpty() ? "" : "\n" + envJson);
        String key = scriptUrl + "\n" + type + "\n" + match + "\n"
                + (bodyRequired ? "1" : "0") + "\n" + envJson;
        if (!seen.add(key)) return;

        JSONObject entry = new JSONObject();
        entry.put("value", scriptUrl);
        String storedMetadata = "FXMETA_B64:" + Base64.encodeToString(
                metadata.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
        if (storedMetadata.length() > 4096) return;
        entry.put("name", storedMetadata);
        entry.put("enabled", !disabled);
        scripts.put(entry);
    }

    private static int indentation(String line) {
        int count = 0;
        while (count < line.length()) {
            char c = line.charAt(count);
            if (c == ' ') count++;
            else if (c == '\t') count += 2;
            else break;
        }
        return count;
    }

    private static String stripComment(String line) {
        boolean singleQuoted = false;
        boolean doubleQuoted = false;
        boolean escaped = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (doubleQuoted) {
                if (escaped) escaped = false;
                else if (c == '\\') escaped = true;
                else if (c == '"') doubleQuoted = false;
            } else if (singleQuoted) {
                if (c == '\'' && i + 1 < line.length() && line.charAt(i + 1) == '\'') i++;
                else if (c == '\'') singleQuoted = false;
            } else if (c == '"') {
                doubleQuoted = true;
            } else if (c == '\'') {
                singleQuoted = true;
            } else if (c == '#' && (i == 0 || Character.isWhitespace(line.charAt(i - 1)))) {
                return line.substring(0, i);
            }
        }
        return line;
    }

    private static String scalar(String raw) {
        if (raw == null) return "";
        String value = raw.trim();
        if (value.length() >= 2 && value.charAt(0) == '"'
                && value.charAt(value.length() - 1) == '"') {
            StringBuilder out = new StringBuilder(value.length() - 2);
            for (int i = 1; i < value.length() - 1; i++) {
                char c = value.charAt(i);
                if (c == '\\' && i + 1 < value.length() - 1) {
                    char next = value.charAt(++i);
                    switch (next) {
                        case 'n': out.append('\n'); break;
                        case 'r': out.append('\r'); break;
                        case 't': out.append('\t'); break;
                        default: out.append(next); break;
                    }
                } else {
                    out.append(c);
                }
            }
            return out.toString().trim();
        }
        if (value.length() >= 2 && value.charAt(0) == '\''
                && value.charAt(value.length() - 1) == '\'') {
            return value.substring(1, value.length() - 1).replace("''", "'").trim();
        }
        if (value.startsWith("[") || value.startsWith("{") || value.startsWith("|")
                || value.startsWith(">") || value.startsWith("&") || value.startsWith("*")
                || value.startsWith("!")) return "";
        return value.trim();
    }

    private static boolean truthy(String value) {
        return "true".equalsIgnoreCase(value) || "yes".equalsIgnoreCase(value) || "1".equals(value);
    }
}
