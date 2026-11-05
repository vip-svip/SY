package de.privacyguard.adhook.imported.shield;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/** Bounded, all-or-nothing parser for the original Shield blacklist preference. */
public final class FxYulongBlacklistPolicy {
    public static final int MAX_RAW_CHARS = 1024 * 1024;
    public static final int MAX_ENTRIES = 10000;

    private FxYulongBlacklistPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    public static boolean isWellFormed(String raw) {
        if (raw == null || raw.isEmpty()) return true;
        if (raw.length() > MAX_RAW_CHARS) return false;
        Set<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) {
            String candidate = item == null ? "" : item.trim();
            if (!isValidPackageName(candidate)) return false;
            packages.add(candidate);
            if (packages.size() > MAX_ENTRIES) return false;
        }
        return true;
    }

    public static Set<String> parse(String raw) {
        if (raw == null || raw.isEmpty()) return Collections.emptySet();
        if (!isWellFormed(raw)) return Collections.emptySet();
        Set<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) packages.add(item.trim());
        return Collections.unmodifiableSet(packages);
    }

    public static String serialize(Iterable<String> packageNames) {
        if (packageNames == null) return null;
        Set<String> unique = new LinkedHashSet<>();
        for (String packageName : packageNames) {
            if (!isValidPackageName(packageName)) return null;
            unique.add(packageName);
            if (unique.size() > MAX_ENTRIES) return null;
        }
        StringBuilder output = new StringBuilder();
        for (String packageName : unique) {
            int extra = packageName.length() + (output.length() == 0 ? 0 : 1);
            if (output.length() + extra > MAX_RAW_CHARS) return null;
            if (output.length() > 0) output.append(',');
            output.append(packageName);
        }
        return output.toString();
    }
}
