package de.privacyguard.adhook.imported.shield;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/** Shared parser and bounded serializer for the original Shield user whitelist preference. */
public final class FxYulongWhitelistPolicy {
    private static final String PREFS = "shield_prefs";
    private static final String KEY = "whitelist_pkgs";
    public static final int MAX_RAW_CHARS = 1024 * 1024;
    public static final int MAX_ENTRIES = 10000;

    private FxYulongWhitelistPolicy() { }

    public static boolean isValidPackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    }

    public static Set<String> parse(String raw) {
        if (raw == null || raw.isEmpty() || raw.length() > MAX_RAW_CHARS) {
            return Collections.emptySet();
        }
        LinkedHashSet<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) {
            String candidate = item == null ? "" : item.trim();
            if (candidate.isEmpty() || !isValidPackageName(candidate)) continue;
            packages.add(candidate);
            if (packages.size() > MAX_ENTRIES) {
                // An oversized/corrupt list must not be partially trusted to suppress
                // risk findings. Fail open so scanning still checks all installed apps.
                return Collections.emptySet();
            }
        }
        return Collections.unmodifiableSet(packages);
    }

    /**
     * Canonical CSV writer shared by the management screen and full-screen picker.
     * Returns null for an invalid package, too many entries, or an oversized payload.
     * Callers must reject the entire write instead of truncating/partially saving it.
     */
    public static String serialize(Iterable<String> packageNames) {
        if (packageNames == null) return null;
        LinkedHashSet<String> unique = new LinkedHashSet<>();
        for (String packageName : packageNames) {
            if (!isValidPackageName(packageName)) return null;
            unique.add(packageName);
            if (unique.size() > MAX_ENTRIES) return null;
        }
        StringBuilder output = new StringBuilder();
        for (String packageName : unique) {
            int additional = packageName.length() + (output.length() == 0 ? 0 : 1);
            if (output.length() + additional > MAX_RAW_CHARS) return null;
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
            if (raw.length() > MAX_RAW_CHARS) {
                android.util.Log.e("FX-YulongShield",
                        "User whitelist exceeded the safe read limit; risk scanning will not suppress findings.");
                return Collections.emptySet();
            }
            // parse() rejects lists above MAX_ENTRIES atomically; exactly MAX_ENTRIES
            // valid packages remain a supported, usable whitelist.
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
