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
    public static final int MAX_LOG_CHARS = 256 * 1024;
    public static final int MAX_EVENTS = 300;
    private static final int MAX_LINE_CHARS = 2048;
    private static final Pattern TAG = Pattern.compile("\\[DIA_([A-Z0-9_]{1,24})\\]");
    private static final Pattern FIELD = Pattern.compile("([A-Za-z][A-Za-z0-9]*)=([^\\s]{1,192})");
    private static final Pattern SAFE_VALUE = Pattern.compile("[A-Za-z0-9_.$:/+@%\\-]{1,160}");
    private static final Pattern NUMBER = Pattern.compile("-?[0-9]{1,12}");

    private static final String[] CATEGORIES = {
            "HTTP", "WebView", "SQL", "算法", "Native", "ClassLoader", "Socket",
            "Intent", "点击", "ViewGroup", "Fragment", "线程", "调用栈",
            "按键", "Runtime", "内存"
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
                out.append("\\n").append(label(item.getKey())).append("：").append(item.getValue());
            }
            if (fields.isEmpty()) out.append("\\n监控事件");
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
                case "view": return "View";
                case "id": return "资源 ID";
                case "parent": return "父 View";
                case "child": return "子 View";
                case "name": return "名称";
                case "keyCode": return "按键码";
                default: return key;
            }
        }
    }

    public static List<Event> parse(String log) {
        if (log == null || log.isEmpty()) return Collections.emptyList();
        String bounded = log.length() > MAX_LOG_CHARS
                ? log.substring(log.length() - MAX_LOG_CHARS) : log;
        ArrayList<Event> events = new ArrayList<>();
        String[] lines = bounded.split("\\r?\\n");
        for (String rawLine : lines) {
            if (rawLine == null || rawLine.length() > MAX_LINE_CHARS) continue;
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
                if (safeFields.size() >= 10) break;
            }
            if (events.size() == MAX_EVENTS) events.remove(0);
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
            case "CLICK":
                return oneOf(key, "view", "id");
            case "VIEWGROUP":
                return oneOf(key, "parent", "child", "id");
            case "THREAD":
                return oneOf(key, "name", "class");
            case "KEY":
                return oneOf(key, "keyCode", "action");
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
                "inputBytes", "outputBytes", "timeoutMs", "requestCode", "id", "keyCode")) {
            return NUMBER.matcher(value).matches();
        }
        // The field allowlist excludes content-bearing keys (SQL, headers, tokens,
        // payloads, stacks and command arguments); this grammar blocks whitespace,
        // control characters, delimiters and URL query/path data in remaining values.
        return SAFE_VALUE.matcher(value).matches();
    }
}
