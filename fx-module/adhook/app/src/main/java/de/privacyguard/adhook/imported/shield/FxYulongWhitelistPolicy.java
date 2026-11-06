package de.privacyguard.adhook.imported.shield;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/** Shared parser and serializer for the original Shield user whitelist preference. */
public final class FxYulongWhitelistPolicy {
    private static final String PREFS = "shield_prefs";
    private static final String KEY = "whitelist_pkgs";

    private FxYulongWhitelistPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    public static boolean isWellFormed(String raw) {
        if (raw == null || raw.isEmpty()) return true;
        LinkedHashSet<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) {
            String candidate = item == null ? "" : item.trim();
            if (!isValidPackageName(candidate)) return false;
            packages.add(candidate);
        }
        return true;
    }

    public static Set<String> parse(String raw) {
        if (raw == null || raw.isEmpty() || !isWellFormed(raw)) {
            // Never partially trust or display a malformed list. Scanning fails open,
            // and management UIs must block writes until the source is repaired.
            return Collections.emptySet();
        }
        LinkedHashSet<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) {
            packages.add(item.trim());
        }
        return Collections.unmodifiableSet(packages);
    }

    /**
     * Canonical CSV writer shared by the management screen and full-screen picker.
     * Returns null for an invalid package; never writes a partial list.
     * Callers must reject the entire write instead of truncating/partially saving it.
     */
    public static String serialize(Iterable<String> packageNames) {
        if (packageNames == null) return null;
        LinkedHashSet<String> unique = new LinkedHashSet<>();
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

    public static Set<String> load(Context context) {
        if (context == null) return Collections.emptySet();
        try {
            SharedPreferences prefs = context.getApplicationContext()
                    .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            String raw = prefs.getString(KEY, "");
            if (raw == null) raw = "";
            // Malformed lists remain rejected atomically by parse().
            return parse(raw);
        } catch (RuntimeException error) {
            android.util.Log.e("FX-YulongShield",
                    "Cannot read user whitelist; risk scanning will continue without suppression.", error);
            return Collections.emptySet();
        }
    }

    public static boolean isWhitelisted(Context context, String packageName) {
        if (!isValidPackageName(packageName)) return false;
        return load(context).contains(packageName);
    }
}
