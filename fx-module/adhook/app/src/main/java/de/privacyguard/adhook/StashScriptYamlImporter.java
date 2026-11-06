package de.privacyguard.adhook;

import android.net.Uri;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Conservative importer for Stash YAML HTTP script configuration.
 *
 * Maps http.script entries through script-providers into FX's HTTPS URL hook
 * contract. Only default FX-compatible options are accepted; Stash-specific
 * engines, non-empty arguments, binary bodies and non-default resource limits
 * are not represented as supported features.
 */
public final class StashScriptYamlImporter {
    private static final class Provider {
        String url = "";
        boolean supported = true;
    }

    private static final class Script {
        String name = "";
        String match = "";
        String type = "";
        String argument = "";
        String engine = "auto";
        String timeout = "";
        String maxSize = "";
        boolean requireBody = false;
        boolean binaryMode = false;
        boolean disabled = false;
        boolean supported = true;
    }

    private StashScriptYamlImporter() {}

    public static JSONObject parse(String yaml) throws JSONException {
        String[] lines = (yaml == null ? "" : yaml).split("\\r?\\n");
        Map<String, Provider> providers = parseProviders(lines);
        JSONArray scripts = new JSONArray();
        Set<String> seen = new HashSet<>();

        boolean inHttp = false;
        boolean inHttpScript = false;
        Script current = null;
        for (String raw : lines) {
            String clean = stripComment(raw);
            if (clean.trim().isEmpty()) continue;
            int indent = indentation(clean);
            String line = clean.trim();

            if (indent == 0) {
                if (current != null) addScript(scripts, seen, current, providers);
                current = null;
                inHttp = "http:".equalsIgnoreCase(line);
                inHttpScript = false;
                continue;
            }
            if (!inHttp) continue;

            if (indent == 2) {
                if ("script:".equalsIgnoreCase(line)) {
                    if (current != null) addScript(scripts, seen, current, providers);
                    current = null;
                    inHttpScript = true;
                } else {
                    if (current != null) addScript(scripts, seen, current, providers);
                    current = null;
                    inHttpScript = false;
                }
                continue;
            }
            if (!inHttpScript) continue;

            if (indent >= 4 && line.startsWith("-")) {
                if (current != null) addScript(scripts, seen, current, providers);
                current = new Script();
                String firstField = line.substring(1).trim();
                if (!firstField.isEmpty()) applyField(current, firstField);
                continue;
            }
            if (current != null && indent >= 6) applyField(current, line);
        }
        if (current != null) addScript(scripts, seen, current, providers);

        if (scripts.length() == 0) {
            throw new IllegalArgumentException(
                    "没有可安全迁移的 Stash http.script 项；需要有效的 HTTPS script-provider、URL match 和 request/response 类型");
        }
        JSONObject document = new JSONObject();
        document.put("format", "FX-SCRIPT-LIST");
        document.put("version", 1);
        document.put("scripts", scripts);
        return document;
    }

    private static Map<String, Provider> parseProviders(String[] lines) {
        Map<String, Provider> providers = new HashMap<>();
        boolean inProviders = false;
        String name = "";
        Provider current = null;
        for (String raw : lines) {
            String clean = stripComment(raw);
            if (clean.trim().isEmpty()) continue;
            int indent = indentation(clean);
            String line = clean.trim();
            if (indent == 0) {
                if (current != null && !name.isEmpty()) providers.put(name, current);
                current = null;
                name = "";
                inProviders = "script-providers:".equalsIgnoreCase(line);
                continue;
            }
            if (!inProviders) continue;
            if (indent == 2 && !line.startsWith("-")) {
                if (current != null && !name.isEmpty()) providers.put(name, current);
                int colon = line.indexOf(':');
                if (colon <= 0) {
                    name = "";
                    current = null;
                    continue;
                }
                name = scalar(line.substring(0, colon));
                current = name.matches("[A-Za-z0-9_.-]{1,128}") ? new Provider() : null;
                continue;
            }
            if (current == null || indent < 4) continue;
            int colon = line.indexOf(':');
            if (colon <= 0) {
                current.supported = false;
                continue;
            }
            String key = line.substring(0, colon).trim().toLowerCase(Locale.ROOT);
            String value = scalar(line.substring(colon + 1));
            if ("url".equals(key)) {
                current.url = value;
            } else if ("interval".equals(key)) {
                if (!defaultInteger(value, 86400)) current.supported = false;
            } else {
                // Provider headers, custom paths, payloads and unknown provider
                // settings are not represented in FX's URL-only subscription model.
                current.supported = false;
            }
        }
        if (current != null && !name.isEmpty()) providers.put(name, current);
        return providers;
    }

    private static void applyField(Script script, String line) {
        int colon = line.indexOf(':');
        if (colon <= 0) {
            script.supported = false;
            return;
        }
        String key = line.substring(0, colon).trim().toLowerCase(Locale.ROOT);
        String value = scalar(line.substring(colon + 1));
        switch (key) {
            case "name": script.name = value; break;
            case "match": script.match = value; break;
            case "type": script.type = value.toLowerCase(Locale.ROOT); break;
            case "require-body":
            case "require_body":
                if (!booleanValue(value, script, true)) script.supported = false;
                break;
            case "binary-mode":
            case "binary_mode":
                if (!booleanValue(value, script, false)) script.supported = false;
                break;
            case "timeout":
                script.timeout = value;
                if (!defaultInteger(value, 10)) script.supported = false;
                break;
            case "max-size":
            case "max_size":
                script.maxSize = value;
                if (!defaultInteger(value, 1048576)) script.supported = false;
                break;
            case "argument":
                script.argument = value;
                // FX carries Stash's per-script argument through the shared metadata
                // header and exposes it to compatible scripts as $argument.
                if (value.length() > 512 || hasControl(value)) script.supported = false;
                break;
            case "engine":
                script.engine = value.toLowerCase(Locale.ROOT);
                if (!script.engine.isEmpty() && !"auto".equals(script.engine)) script.supported = false;
                break;
            case "disabled":
                if ("true".equalsIgnoreCase(value) || "yes".equalsIgnoreCase(value) || "1".equals(value)) {
                    script.disabled = true;
                } else if ("false".equalsIgnoreCase(value) || "no".equalsIgnoreCase(value)
                        || "0".equals(value) || value.isEmpty()) {
                    script.disabled = false;
                } else {
                    script.supported = false;
                }
                break;
            default:
                // Reject unknown script options rather than silently dropping their semantics.
                script.supported = false;
                break;
        }
    }

    private static boolean booleanValue(String value, Script script, boolean requireBody) {
        if ("true".equalsIgnoreCase(value) || "yes".equalsIgnoreCase(value) || "1".equals(value)) {
            if (requireBody) script.requireBody = true;
            else script.binaryMode = true;
            return true;
        }
        if ("false".equalsIgnoreCase(value) || "no".equalsIgnoreCase(value) || "0".equals(value)
                || value.isEmpty()) {
            if (requireBody) script.requireBody = false;
            else script.binaryMode = false;
            return true;
        }
        return false;
    }

    private static void addScript(JSONArray output, Set<String> seen, Script script,
                                  Map<String, Provider> providers) throws JSONException {
        if (!script.supported || script.name.isEmpty() || script.match.isEmpty()
                || script.match.length() > 2048 || hasControl(script.match)
                || !script.match.matches("(?is).*https?://.*")) return;
        if (!"request".equals(script.type) && !"response".equals(script.type)) return;
        Provider provider = providers.get(script.name);
        if (provider == null || !provider.supported || provider.url.isEmpty()
                || provider.url.length() > 2048 || hasControl(provider.url)
                || !provider.url.regionMatches(true, 0, "https://", 0, 8)) return;

        Uri uri = Uri.parse(provider.url);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getPort() > 65535) return;

        String displayName = script.name.replaceAll("[\\p{Cntrl}]", " ").trim();
        if (displayName.isEmpty() || displayName.length() > 512) return;
        String bodyFlag = script.requireBody ? "1" : "0";
        // Metadata field 5 is reserved for Egern env JSON; preserve an empty
        // slot so Stash's argument remains field 6 for the shared runtime bridge.
        String metadata = script.type + "\n" + script.match + "\n"
                + bodyFlag + "\n" + displayName + "\n\n" + script.argument;
        String duplicateKey = provider.url + "\n" + script.type + "\n"
                + script.match + "\n" + bodyFlag + "\n" + script.argument;
        if (!seen.add(duplicateKey)) return;

        String encoded = "FXMETA_B64:" + Base64.encodeToString(
                metadata.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
        if (encoded.length() > 4096) return;
        JSONObject entry = new JSONObject();
        entry.put("value", provider.url);
        entry.put("name", encoded);
        entry.put("enabled", !script.disabled);
        output.put(entry);
    }

    private static boolean defaultInteger(String raw, int expected) {
        if (raw == null || raw.trim().isEmpty()) return true;
        try {
            return Integer.parseInt(raw.trim()) == expected;
        } catch (NumberFormatException invalid) {
            return false;
        }
    }

    private static boolean truthy(String value) {
        return "true".equalsIgnoreCase(value) || "yes".equalsIgnoreCase(value) || "1".equals(value);
    }

    private static boolean hasControl(String value) {
        if (value == null) return true;
        for (int i = 0; i < value.length(); i++) {
            if (Character.isISOControl(value.charAt(i))) return true;
        }
        return false;
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
        boolean single = false;
        boolean dual = false;
        boolean escaped = false;
        for (int i = 0; i < line.length(); i++) {
            char c = line.charAt(i);
            if (dual) {
                if (escaped) escaped = false;
                else if (c == '\\') escaped = true;
                else if (c == '"') dual = false;
            } else if (single) {
                if (c == '\'' && i + 1 < line.length() && line.charAt(i + 1) == '\'') i++;
                else if (c == '\'') single = false;
            } else if (c == '"') dual = true;
            else if (c == '\'') single = true;
            else if (c == '#' && (i == 0 || Character.isWhitespace(line.charAt(i - 1)))) return line.substring(0, i);
        }
        return line;
    }

    private static String scalar(String raw) {
        if (raw == null) return "";
        String value = raw.trim();
        if (value.length() >= 2 && value.charAt(0) == '"' && value.charAt(value.length() - 1) == '"') {
            StringBuilder out = new StringBuilder();
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
                } else out.append(c);
            }
            return out.toString().trim();
        }
        if (value.length() >= 2 && value.charAt(0) == '\'' && value.charAt(value.length() - 1) == '\'') {
            return value.substring(1, value.length() - 1).replace("''", "'").trim();
        }
        if (value.startsWith("[") || value.startsWith("{") || value.startsWith("|")
                || value.startsWith(">") || value.startsWith("&") || value.startsWith("*")
                || value.startsWith("!")) return "";
        return value.trim();
    }
}
