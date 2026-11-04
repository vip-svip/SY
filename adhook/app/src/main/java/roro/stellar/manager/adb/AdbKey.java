package roro.stellar.manager.adb;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.net.ssl.SSLContext;

/** Stable host identity and TLS context for the original Stellar ADB pairing flow. */
public final class AdbKey {
    private static final String IDENTITY = "youlong";

    private final java.security.KeyPair keyPair;
    private final RSAPrivateKey privateKey;
    private final RSAPublicKey publicKey;
    private final java.security.cert.X509Certificate certificate;
    private final SSLContext sslContext;
    private final String identity;

    private AdbKey(Context context, String identity)
            throws GeneralSecurityException, IOException {
        if (context == null) throw new IllegalArgumentException("Context is null");
        Context storage = context.createDeviceProtectedStorageContext();
        SharedPreferences preferences = storage.getSharedPreferences("settings", Context.MODE_PRIVATE);
        this.identity = validateIdentity(identity);
        this.keyPair = loadKeyPair(preferences);
        this.privateKey = (RSAPrivateKey) keyPair.getPrivate();
        this.publicKey = (RSAPublicKey) keyPair.getPublic();
        this.certificate = AdbClientCertificate.create(publicKey, privateKey);
        this.sslContext = AdbTlsContext.create(keyPair);
    }

    private AdbKey(SharedPreferences preferences, String identity)
            throws GeneralSecurityException {
        if (preferences == null) throw new IllegalArgumentException("ADB preferences are null");
        this.identity = validateIdentity(identity);
        this.keyPair = loadKeyPair(preferences);
        this.privateKey = (RSAPrivateKey) keyPair.getPrivate();
        this.publicKey = (RSAPublicKey) keyPair.getPublic();
        this.certificate = AdbClientCertificate.create(publicKey, privateKey);
        this.sslContext = AdbTlsContext.create(keyPair);
    }

    public static AdbKey getOrCreate(Context context)
            throws GeneralSecurityException, IOException {
        return new AdbKey(context, IDENTITY);
    }

    static AdbKey getOrCreateForTesting(SharedPreferences preferences, String identity)
            throws GeneralSecurityException {
        return new AdbKey(preferences, identity);
    }

    private static String validateIdentity(String value) {
        if (value == null || value.isEmpty() || value.length() > 64
                || !value.matches("[A-Za-z0-9_.@-]+")) {
            throw new IllegalArgumentException("ADB host identity is invalid");
        }
        return value;
    }

    private static java.security.KeyPair loadKeyPair(SharedPreferences preferences)
            throws GeneralSecurityException {
        AdbPrivateKeyVault vault = new AdbPrivateKeyVault(
                new PreferenceAdbKeyStore(preferences),
                AndroidAdbEncryptionKey.getOrCreate());
        java.security.KeyPair pair = vault.loadOrCreate();
        if (!(pair.getPrivate() instanceof RSAPrivateKey)
                || !(pair.getPublic() instanceof RSAPublicKey)) {
            throw new GeneralSecurityException("ADB vault returned an incompatible RSA key pair");
        }
        return pair;
    }


    public SSLContext getSslContext() { return sslContext; }
    public RSAPrivateKey getPrivateKey() { return privateKey; }
    public RSAPublicKey getPublicKey() { return publicKey; }
    public X509Certificate getCertificate() { return certificate; }

    /**
     * ADB AUTH token is already a 20-byte SHA-1 prehash. Encode the SHA-1
     * DigestInfo inside EMSA-PKCS1-v1_5 and perform one RSA private operation.
     */
    public byte[] sign(byte[] token) throws GeneralSecurityException {
        return AdbAuthSignature.sign(privateKey, token);
    }

    /** ADB peer-info record contains Base64(524-byte adb_rsa_pubkey) + comment + NUL. */
    public byte[] getAdbPublicKey() {
        return AdbPublicKeyEncoder.encode(publicKey, identity);
    }

}
