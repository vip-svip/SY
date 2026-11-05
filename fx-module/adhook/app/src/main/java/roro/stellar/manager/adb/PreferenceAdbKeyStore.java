package roro.stellar.manager.adb;

import android.content.SharedPreferences;
import android.util.Base64;

/** Original ADB key preference format: key name "adbkey", Base64 without line wrapping. */
public final class PreferenceAdbKeyStore implements AdbKeyStore {
    private static final String PREFERENCE_KEY = "adbkey";
    private final SharedPreferences preferences;

    public PreferenceAdbKeyStore(SharedPreferences preferences) {
        if (preferences == null) throw new IllegalArgumentException("preferences are required");
        this.preferences = preferences;
    }

    @Override
    public byte[] get() {
        if (!preferences.contains(PREFERENCE_KEY)) return null;
        String encoded = preferences.getString(PREFERENCE_KEY, null);
        if (encoded == null) return null;
        try {
            byte[] decoded = Base64.decode(encoded, Base64.NO_WRAP);
            if (decoded.length < 28 || decoded.length > 16384) {
                java.util.Arrays.fill(decoded, (byte) 0);
                throw new IllegalStateException("stored ADB key has an invalid encrypted length");
            }
            return decoded;
        } catch (IllegalArgumentException malformed) {
            throw new IllegalStateException("stored ADB key is not valid Base64; refusing silent identity rotation", malformed);
        }
    }

    @Override
    public void put(byte[] encryptedKey) {
        if (encryptedKey == null || encryptedKey.length < 28 || encryptedKey.length > 16384) {
            throw new IllegalArgumentException("encrypted ADB key is outside the allowed size");
        }
        String encoded = Base64.encodeToString(encryptedKey, Base64.NO_WRAP);
        if (!preferences.edit().putString(PREFERENCE_KEY, encoded).commit()) {
            throw new IllegalStateException("ADB key preference could not be committed");
        }
    }
}
