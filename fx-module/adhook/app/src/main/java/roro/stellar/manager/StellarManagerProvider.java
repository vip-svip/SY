package roro.stellar.manager;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Compatibility data endpoint retained at the original Stellar provider
 * authority. It preserves the original config/log call contract without
 * pretending that FX's Messenger authorization service is the old AIDL daemon.
 *
 * The original provider protected this exported endpoint with
 * INTERACT_ACROSS_USERS_FULL. Keep that manifest boundary; do not make it
 * available to ordinary third-party apps.
 */
public final class StellarManagerProvider extends ContentProvider {
    public static final String METHOD_SAVE_LOG = "saveLog";
    public static final String METHOD_GET_SHIZUKU_COMPAT = "getShizukuCompat";
    public static final String METHOD_SAVE_CONFIG = "saveConfig";
    public static final String METHOD_GET_LOGS = "getLogs";
    public static final String METHOD_LOAD_CONFIG = "loadConfig";
    public static final String METHOD_CLEAR_LOGS = "clearLogs";

    public static final String KEY_LOGS = "logs";
    public static final String KEY_PACKAGES_JSON = "packagesJson";
    public static final String KEY_SHIZUKU_COMPAT = "shizukuCompat";
    public static final String KEY_CONFIG_JSON = "configJson";

    private static final String PREFS = "fx_stellar_manager_provider";
    private static final String KEY_ACCESSIBILITY_AUTO_START = "accessibilityAutoStart";
    private static final String KEY_DAEMON_ENABLED = "daemonEnabled";
    private static final String KEY_PACKAGES = "packages";
    private static final String KEY_LOG_ENTRIES = "logEntries";
    private static final int CONFIG_LIMIT = 1024 * 1024;
    private static final int MAX_PACKAGE_ENTRIES = 4096;
    private static final int MAX_LOG_ENTRIES = 500;
    private static final int MAX_LOG_CHARS = 4096;

    private SharedPreferences preferences;

    @Override public boolean onCreate() {
        Context context = getContext();
        if (context == null) return false;
        if (Build.VERSION.SDK_INT >= 24) {
            context = context.createDeviceProtectedStorageContext();
        }
        preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        return preferences != null;
    }

    private JSONObject normalizedConfig(String raw) throws JSONException {
        if (raw == null || raw.isEmpty() || raw.length() > CONFIG_LIMIT) {
            throw new JSONException("Stellar config is empty or exceeds the size limit");
        }
        JSONObject input = new JSONObject(raw);
        JSONObject packages = input.optJSONObject("packages");
        if (input.has("packages") && packages == null) {
            throw new JSONException("Stellar packages must be a JSON object");
        }
        if (packages == null) packages = new JSONObject();
        if (packages.length() > MAX_PACKAGE_ENTRIES) {
            throw new JSONException("Stellar package map exceeds the entry limit");
        }

        // StellarConfig uses Map<Integer, PackageEntry>. Keep the original
        // PackageEntry payload intact while validating map keys and value types.
        List<String> keys = new ArrayList<>();
        for (java.util.Iterator<String> it = packages.keys(); it.hasNext();) {
            String key = it.next();
            try {
                int uid = Integer.parseInt(key);
                if (uid < 0) throw new NumberFormatException("negative UID");
            } catch (NumberFormatException invalid) {
                throw new JSONException("Invalid Stellar package UID key");
            }
            if (!(packages.opt(key) instanceof JSONObject)) {
                throw new JSONException("Stellar package entry must be an object");
            }
            keys.add(key);
        }

        JSONObject result = new JSONObject();
        result.put("version", 1);
        result.put("accessibilityAutoStart", input.optBoolean("accessibilityAutoStart", false));
        result.put("daemonEnabled", input.optBoolean("daemonEnabled", false));
        // The original provider forces Shizuku compatibility on when saving
        // and defaults it to on when loading, regardless of the input JSON.
        result.put("shizukuCompatEnabled", true);
        result.put("packages", packages);
        return result;
    }

    private List<String> readLogs() {
        String encoded = preferences.getString(KEY_LOG_ENTRIES, "[]");
        if (encoded == null || encoded.isEmpty() || encoded.length() > CONFIG_LIMIT) {
            return new ArrayList<>();
        }
        try {
            org.json.JSONArray array = new org.json.JSONArray(encoded);
            List<String> logs = new ArrayList<>();
            int start = Math.max(0, array.length() - MAX_LOG_ENTRIES);
            for (int i = start; i < array.length(); i++) {
                Object value = array.opt(i);
                if (value instanceof String) logs.add((String) value);
            }
            return logs;
        } catch (JSONException invalid) {
            return new ArrayList<>();
        }
    }

    private boolean writeLogs(List<String> logs) {
        org.json.JSONArray array = new org.json.JSONArray();
        int start = Math.max(0, logs.size() - MAX_LOG_ENTRIES);
        for (int i = start; i < logs.size(); i++) array.put(logs.get(i));
        return preferences.edit().putString(KEY_LOG_ENTRIES, array.toString()).commit();
    }

    @Override public synchronized Bundle call(String method, String arg, Bundle extras) {
        if (preferences == null || method == null) return null;
        switch (method) {
            case METHOD_SAVE_LOG: {
                if (arg == null || arg.isEmpty() || arg.length() > MAX_LOG_CHARS) return null;
                List<String> logs = readLogs();
                logs.add(arg);
                if (!writeLogs(logs)) return null;
                return new Bundle();
            }
            case METHOD_GET_SHIZUKU_COMPAT: {
                Bundle result = new Bundle();
                result.putBoolean(KEY_SHIZUKU_COMPAT,
                        preferences.getBoolean(KEY_SHIZUKU_COMPAT, true));
                return result;
            }
            case METHOD_SAVE_CONFIG: {
                if (extras == null) return null;
                String raw = extras.getString(KEY_CONFIG_JSON);
                try {
                    JSONObject config = normalizedConfig(raw);
                    JSONObject packages = config.getJSONObject("packages");
                    boolean saved = preferences.edit()
                            .putBoolean(KEY_ACCESSIBILITY_AUTO_START,
                                    config.getBoolean("accessibilityAutoStart"))
                            .putBoolean(KEY_DAEMON_ENABLED, config.getBoolean("daemonEnabled"))
                            .putBoolean(KEY_SHIZUKU_COMPAT, true)
                            .putString(KEY_PACKAGES, packages.toString())
                            .commit();
                    return saved ? new Bundle() : null;
                } catch (JSONException invalid) {
                    return null;
                }
            }
            case METHOD_GET_LOGS: {
                List<String> logs = readLogs();
                Bundle result = new Bundle();
                result.putStringArray(KEY_LOGS, logs.toArray(new String[0]));
                return result;
            }
            case METHOD_LOAD_CONFIG: {
                try {
                    JSONObject packages = new JSONObject(
                            preferences.getString(KEY_PACKAGES, "{}"));
                    JSONObject config = new JSONObject();
                    config.put("version", 1);
                    config.put("accessibilityAutoStart",
                            preferences.getBoolean(KEY_ACCESSIBILITY_AUTO_START, false));
                    config.put("daemonEnabled",
                            preferences.getBoolean(KEY_DAEMON_ENABLED, false));
                    config.put("shizukuCompatEnabled",
                            preferences.getBoolean(KEY_SHIZUKU_COMPAT, true));
                    config.put("packages", packages);
                    Bundle result = new Bundle();
                    result.putString(KEY_CONFIG_JSON, config.toString());
                    return result;
                } catch (JSONException invalidStoredState) {
                    // Corrupt legacy state must not crash ContentProvider callers.
                    JSONObject defaults = new JSONObject();
                    try {
                        defaults.put("version", 1);
                        defaults.put("accessibilityAutoStart", false);
                        defaults.put("daemonEnabled", false);
                        defaults.put("shizukuCompatEnabled", true);
                        defaults.put("packages", new JSONObject());
                    } catch (JSONException impossible) {
                        return null;
                    }
                    Bundle result = new Bundle();
                    result.putString(KEY_CONFIG_JSON, defaults.toString());
                    return result;
                }
            }
            case METHOD_CLEAR_LOGS: {
                boolean cleared = preferences.edit().remove(KEY_LOG_ENTRIES).commit();
                return cleared ? new Bundle() : null;
            }
            default:
                // getBinder/sendBinder/sendUserService belong to the original
                // Stellar AIDL daemon contract. FX does not claim to implement
                // that daemon and therefore never returns a misleading Binder.
                return null;
        }
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
                                  String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override public String getType(Uri uri) {
        return null;
    }

    @Override public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override public int update(Uri uri, ContentValues values, String selection,
                                String[] selectionArgs) {
        return 0;
    }
}
