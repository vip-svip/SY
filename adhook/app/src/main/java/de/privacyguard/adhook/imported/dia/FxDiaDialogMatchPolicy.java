package de.privacyguard.adhook.imported.dia;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Bounded literal matcher used to identify explicitly configured app dialogs. */
public final class FxDiaDialogMatchPolicy {
    public static final int MAX_RAW_UTF8_BYTES = 1024;
    public static final int MAX_TERMS = 32;
    public static final int MAX_TERM_CHARS = 96;
    public static final int MAX_TEXT_CHARS = 4096;

    private FxDiaDialogMatchPolicy() { }

    public static List<String> parseTerms(String raw) {
        if (raw == null || raw.trim().isEmpty()) return Collections.emptyList();
        if (raw.getBytes(StandardCharsets.UTF_8).length > MAX_RAW_UTF8_BYTES)
            throw new IllegalArgumentException("规则文本超过 1 KiB。");
        Map<String, String> unique = new LinkedHashMap<>();
        for (String line : raw.split("\\R", -1)) {
            String term = line == null ? "" : line.trim();
            if (term.isEmpty()) continue;
            if (term.length() > MAX_TERM_CHARS)
                throw new IllegalArgumentException("单条规则不能超过 96 个字符。");
            for (int i = 0; i < term.length(); i++) {
                if (Character.isISOControl(term.charAt(i)))
                    throw new IllegalArgumentException("规则不能包含控制字符。");
            }
            String key = term.toLowerCase(Locale.ROOT);
            if (!unique.containsKey(key)) unique.put(key, term);
            if (unique.size() > MAX_TERMS)
                throw new IllegalArgumentException("最多允许 32 条规则。");
        }
        return Collections.unmodifiableList(new ArrayList<>(unique.values()));
    }

    public static String normalizeTerms(String raw) {
        return String.join("\n", parseTerms(raw));
    }

    public static boolean matchesText(CharSequence text, List<String> terms) {
        if (text == null || terms == null || terms.isEmpty()) return false;
        int count = Math.min(text.length(), MAX_TEXT_CHARS);
        String candidate = text.subSequence(0, count).toString().toLowerCase(Locale.ROOT);
        for (String term : terms) {
            if (term != null && !term.isEmpty()
                    && candidate.contains(term.toLowerCase(Locale.ROOT))) return true;
        }
        return false;
    }

    public static boolean matchesResourceId(int id, String fullName, String entryName,
                                             List<String> terms) {
        if (id == 0 || terms == null || terms.isEmpty()) return false;
        String decimal = Integer.toString(id);
        String hex = "0x" + Integer.toHexString(id);
        for (String term : terms) {
            if (term == null || term.isEmpty()) continue;
            if (term.equalsIgnoreCase(decimal) || term.equalsIgnoreCase(hex)
                    || (fullName != null && term.equalsIgnoreCase(fullName))
                    || (entryName != null && term.equalsIgnoreCase(entryName))) return true;
        }
        return false;
    }
}
