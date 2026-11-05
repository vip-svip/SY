package roro.stellar.manager.adb;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;

import java.security.GeneralSecurityException;
import java.security.Key;
import java.security.KeyStore;

import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

/** AndroidKeyStore AES-256/GCM key with the original Stellar alias and purposes. */
public final class AndroidAdbEncryptionKey {
    public static final String ALIAS = "_adbkey_encryption_key_";

    private AndroidAdbEncryptionKey() { }

    public static SecretKey getOrCreate() throws GeneralSecurityException {
        try {
            KeyStore store = KeyStore.getInstance("AndroidKeyStore");
            store.load(null);
            Key existing = store.getKey(ALIAS, null);
            if (existing != null) {
                if (!(existing instanceof SecretKey)) {
                    throw new GeneralSecurityException("ADB encryption alias is not an AES secret key");
                }
                return (SecretKey) existing;
            }

            KeyGenerator generator = KeyGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(
                    ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build();
            generator.init(spec);
            return generator.generateKey();
        } catch (GeneralSecurityException failure) {
            throw failure;
        } catch (Exception failure) {
            throw new GeneralSecurityException("Unable to access AndroidKeyStore ADB key", failure);
        }
    }
}
