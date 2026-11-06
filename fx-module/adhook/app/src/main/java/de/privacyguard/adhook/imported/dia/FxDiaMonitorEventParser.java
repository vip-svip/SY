package de.privacyguard.adhook.imported.dia;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Parses only the built-in Dia monitor event contract.
 *
 * Arbitrary Frida console text, SQL text, HTTP bodies, headers, command contents,
 * stack traces, filesystem paths and custom script messages are never returned.
 */
public final class FxDiaMonitorEventParser {
    private static final Pattern TAG = Pattern.compile("\\[DIA_([A-Z0-9_]+)\\]");
    private static final Pattern FIELD = Pattern.compile("([A-Za-z][A-Za-z0-9]*)=([^\\s]+)");
    private static final Pattern SAFE_VALUE = Pattern.compile("[A-Za-z0-9_.$:/+@%\\-]+");
    private static final Pattern HOST_LABEL = Pattern.compile("(?i)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?");
    private static final Pattern IDENTIFIER = Pattern.compile("[A-Za-z0-9_.$-]+");
    private static final Pattern COMPONENT = Pattern.compile("[A-Za-z0-9_.$/-]+");
    private static final Pattern PACKAGE_NAME = Pattern.compile("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+");
    private static final Pattern NUMBER = Pattern.compile("-?[0-9]{1,12}");

    private static final String[] CATEGORIES = {
            "HTTP", "WebView", "SQL", "算法", "Native", "ClassLoader", "Socket",
            "Intent", "Activity 入口", "点击", "ViewGroup", "Fragment", "线程",
            "调用栈", "按键", "Runtime", "内存"
    };

    private FxDiaMonitorEventParser() { }

    public static String[] getCategories() {
        return CATEGORIES.clone();
    }

    public static final class Event {
        public final String tag;
        public final String category;
        public final Map<String, String> fields;

        private Event(String eventTag, String eventCategory, Map<String, String> safeFields) {
            tag = eventTag;
            category = eventCategory;
            fields = Collections.unmodifiableMap(new LinkedHashMap<>(safeFields));
        }

        public String toDisplayString() {
            StringBuilder out = new StringBuilder(category);
            for (Map.Entry<String, String> item : fields.entrySet()) {
                out.append("\n").append(label(item.getKey())).append("：").append(item.getValue());
            }
            if (fields.isEmpty()) out.append("\n监控事件");
            return out.toString();
        }

        private static String label(String key) {
            switch (key) {
                case "method": return "方法";
                case "host": return "主机";
                case "status": return "状态码";
                case "elapsedMs": return "耗时(ms)";
                case "bodyBytes": return "正文长度(bytes)";
                case "class": return "类";
                case "args": return "参数数";
                case "firstStringLength": return "首个字符串长度";
                case "exception": return "异常类型";
                case "family": return "算法族";
                case "algorithm": return "算法";
                case "inputBytes": return "输入长度(bytes)";
                case "outputBytes": return "输出长度(bytes)";
                case "loader": return "加载器";
                case "endpoint": return "端点";
                case "timeoutMs": return "超时(ms)";
                case "action": return "Action";
                case "component": return "组件";
                case "requestCode": return "请求码";
                case "stage": return "阶段";
                case "activity": return "Activity";
                case "intentPackage": return "Intent 包名";
                case "view": return "View";
                case "id": return "资源 ID";
                case "parent": return "父 View";
                case "child": return "子 View";
                case "name": return "名称";
                case "keyCode": return "按键码";
                case "depth": return "深度";
                default: return key;
            }
        }
    }

    public static List<Event> parse(String log) {
        if (log == null || log.isEmpty()) return Collections.emptyList();
        String bounded = log;
        ArrayList<Event> events = new ArrayList<>();
        String[] lines = bounded.split("\\r?\\n");
        for (String rawLine : lines) {
            if (rawLine == null) continue;
            Matcher tagMatcher = TAG.matcher(rawLine);
            if (!tagMatcher.find()) continue;
            String tag = tagMatcher.group(1);
            String category = categoryFor(tag);
            if (category == null) continue;

            LinkedHashMap<String, String> safeFields = new LinkedHashMap<>();
            Matcher fieldMatcher = FIELD.matcher(rawLine.substring(tagMatcher.end()));
            while (fieldMatcher.find()) {
                String key = fieldMatcher.group(1);
                if (!allowedField(tag, key)) continue;
                String value = fieldMatcher.group(2);
                if (!isSafeValue(key, value)) continue;
                safeFields.put(key, value);
            }
            events.add(new Event(tag, category, safeFields));
        }
        return Collections.unmodifiableList(events);
    }

    private static String categoryFor(String tag) {
        switch (tag) {
            case "HTTP": return "HTTP";
            case "WEBVIEW": return "WebView";
            case "SQL": return "SQL";
            case "ALGORITHM": return "算法";
            case "NATIVE": return "Native";
            case "CLASSLOADER": return "ClassLoader";
            case "SOCKET": return "Socket";
            case "INTENT": return "Intent";
            case "APPENTRY": return "Activity 入口";
            case "CLICK": return "点击";
            case "VIEWGROUP": return "ViewGroup";
            case "FRAGMENT": return "Fragment";
            case "THREAD": return "线程";
            case "STACK": return "调用栈";
            case "KEY": return "按键";
            case "RUNTIME": return "Runtime";
            case "MEMORY": return "内存";
            default: return null;
        }
    }

    private static boolean allowedField(String tag, String key) {
        switch (tag) {
            case "HTTP":
                return oneOf(key, "method", "host", "status", "elapsedMs", "exception");
            case "WEBVIEW":
                return oneOf(key, "host", "bodyBytes");
            case "SQL":
                return oneOf(key, "class", "method", "args", "firstStringLength", "elapsedMs", "exception");
            case "ALGORITHM":
                return oneOf(key, "family", "algorithm", "method", "inputBytes", "outputBytes",
                        "elapsedMs", "exception");
            case "NATIVE":
                return oneOf(key, "elapsedMs");
            case "CLASSLOADER":
                return oneOf(key, "class", "loader");
            case "SOCKET":
                return oneOf(key, "endpoint", "timeoutMs", "elapsedMs", "exception");
            case "INTENT":
                return oneOf(key, "action", "component", "requestCode");
            case "APPENTRY":
                // Activity observer records only class/launch metadata. Intent
                // extras, URI data, component object and payload are never shown.
                return oneOf(key, "stage", "activity", "action", "intentPackage");
            case "CLICK":
                return oneOf(key, "view", "id");
            case "VIEWGROUP":
                return oneOf(key, "parent", "child", "id");
            case "THREAD":
                return oneOf(key, "name", "class");
            case "KEY":
                return oneOf(key, "keyCode", "action");
            case "FRAGMENT":
                return oneOf(key, "stage", "class", "method");
            case "STACK":
                return oneOf(key, "class", "method", "depth");
            case "RUNTIME":
                return oneOf(key, "class", "method", "args", "elapsedMs", "exception");
            case "MEMORY":
                return oneOf(key, "stage", "inputBytes", "outputBytes");
            default:
                return false;
        }
    }

    private static boolean oneOf(String value, String... choices) {
        for (String choice : choices) if (choice.equals(value)) return true;
        return false;
    }

    private static boolean isSafeValue(String key, String value) {
        if (value == null || value.isEmpty()) return false;
        if (oneOf(key, "status", "elapsedMs", "bodyBytes", "args", "firstStringLength",
                "inputBytes", "outputBytes", "timeoutMs", "requestCode", "id", "keyCode", "depth")) {
            return NUMBER.matcher(value).matches();
        }
        // Host/endpoint fields are authorities only: no scheme, user-info, path,
        // query or fragment may reach the UI.
        if (oneOf(key, "host", "endpoint")) return isSafeAuthority(value);
        if ("intentPackage".equals(key)) return PACKAGE_NAME.matcher(value).matches();
        if ("component".equals(key)) return COMPONENT.matcher(value).matches();
        if (oneOf(key, "method", "class", "loader", "exception", "family", "algorithm",
                "stage", "activity", "name", "action", "view", "parent", "child")) {
            return IDENTIFIER.matcher(value).matches();
        }
        return SAFE_VALUE.matcher(value).matches();
    }

    private static boolean isSafeAuthority(String value) {
        if (value == null || value.isEmpty() || value.length() > 260) return false;
        String host = value;
        String port = null;
        if (value.charAt(0) == '[') {
            int close = value.indexOf(']');
            if (close < 0) return false;
            String address = value.substring(1, close);
            if (address.indexOf(':') < 0 || !address.matches("[0-9A-Fa-f:.]{2,45}")) return false;
            String suffix = value.substring(close + 1);
            if (!suffix.isEmpty()) {
                if (suffix.charAt(0) != ':' || suffix.length() == 1) return false;
                port = suffix.substring(1);
            }
        } else {
            int colon = value.lastIndexOf(':');
            if (colon >= 0) {
                if (value.indexOf(':') != colon || colon == 0 || colon == value.length() - 1) return false;
                host = value.substring(0, colon);
                port = value.substring(colon + 1);
            }
            if (host.isEmpty() || host.length() > 253) return false;
            if (host.matches("[0-9.]+")) {
                String[] octets = host.split("\\.", -1);
                if (octets.length != 4) return false;
                for (String octet : octets) {
                    if (octet.isEmpty() || octet.length() > 3) return false;
                    try {
                        if (Integer.parseInt(octet) > 255) return false;
                    } catch (NumberFormatException invalid) {
                        return false;
                    }
                }
            } else {
                for (String label : host.split("\\.", -1)) {
                    if (!HOST_LABEL.matcher(label).matches()) return false;
                }
            }
        }
        if (port != null) {
            if (!port.matches("[0-9]{1,5}")) return false;
            try {
                int number = Integer.parseInt(port);
                if (number < 1 || number > 65535) return false;
            } catch (NumberFormatException invalid) {
                return false;
            }
        }
        return true;
    }
}
