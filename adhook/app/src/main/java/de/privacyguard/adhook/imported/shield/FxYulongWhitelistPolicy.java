package de.privacyguard.adhook.imported.shield;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

/** Shared parser for the original Shield user whitelist preference. */
public final class FxYulongWhitelistPolicy {
    private static final String PREFS = "shield_prefs";
    private static final String KEY = "whitelist_pkgs";
    public static final int MAX_RAW_CHARS = 1024 * 1024;
    public static final int MAX_ENTRIES = 10000;

    private FxYulongWhitelistPolicy() { }

    public static Set<String> parse(String raw) {
        if (raw == null || raw.isEmpty() || raw.length() > MAX_RAW_CHARS) {
            return Collections.emptySet();
        }
        LinkedHashSet<String> packages = new LinkedHashSet<>();
        for (String item : raw.split(",", -1)) {
            String candidate = item == null ? "" : item.trim();
            if (candidate.isEmpty()) continue;
            if (candidate.length() > 255
                    || !candidate.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) {
                continue;
            }
            packages.add(candidate);
            if (packages.size() > MAX_ENTRIES) {
                // An oversized/corrupt list must not be partially trusted to suppress
                // risk findings. Fail open so scanning still checks all installed apps.
                return Collections.emptySet();
            }
        }
        return Collections.unmodifiableSet(packages);
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
        if (packageName == null || packageName.length() > 255
                || !packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")) {
            return false;
        }
        return load(context).contains(packageName);
    }
}
