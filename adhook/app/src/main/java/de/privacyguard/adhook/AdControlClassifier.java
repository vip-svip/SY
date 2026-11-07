package de.privacyguard.adhook;

import java.util.Locale;

/** Pure text classifier for controls that must never be hidden as advertisements. */
public final class AdControlClassifier {
    private AdControlClassifier() {}

    public static boolean isProtectedText(String value) {
        String text = value == null ? "" : value.toLowerCase(Locale.ROOT).trim();
        if (text.isEmpty()) return false;
        return text.equals("skip") || text.equals("skip ad") || text.equals("close")
                || text.equals("close ad") || text.equals("ad choices")
                || text.contains("countdown") || text.contains("跳过")
                || text.contains("关闭") || text.contains("倒计时")
                || text.matches(".*\\d+\\s*秒后.*");
    }
}
