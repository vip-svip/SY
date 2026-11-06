package de.privacyguard.adhook.imported.shield;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/** All-or-nothing parser for the original Shield blacklist preference. */
public final class FxYulongBlacklistPolicy {

    private FxYulongBlacklistPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    public static boolean isWellFormed(String raw) {
        if (raw == null || raw.isEmpty()) return true;
        Set<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) {
            String candidate = item == null ? "" : item.trim();
            if (!isValidPackageName(candidate)) return false;
            packages.add(candidate);
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
        }
        StringBuilder output = new StringBuilder();
        for (String packageName : unique) {
            if (output.length() > 0) output.append(',');
            output.append(packageName);
        }
        return output.toString();
    }
}
