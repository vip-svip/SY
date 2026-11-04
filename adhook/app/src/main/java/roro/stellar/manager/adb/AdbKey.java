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
    private static final byte[] ADB_AUTH_PADDING = createAdbAuthPadding();

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

    private static byte[] createAdbAuthPadding() {
        byte[] padding = new byte[236];
        padding[0] = 0;
        padding[1] = 1;
        Arrays.fill(padding, 2, padding.length, (byte) 0xff);
        return padding;
    }

    public SSLContext getSslContext() { return sslContext; }
    public RSAPrivateKey getPrivateKey() { return privateKey; }
    public RSAPublicKey getPublicKey() { return publicKey; }
    public X509Certificate getCertificate() { return certificate; }

    /**
     * Original ADB AUTH signature: raw RSA private operation over the 236-byte
     * 00 01 FF... block followed by the 20-byte daemon challenge. This is not
     * SHA1withRSA DigestInfo encoding.
     */
    public byte[] sign(byte[] token) throws GeneralSecurityException {
        if (token == null || token.length != 20) {
            throw new GeneralSecurityException("ADB AUTH challenge must be exactly 20 bytes");
        }
        Cipher cipher = Cipher.getInstance("RSA/ECB/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, privateKey);
        cipher.update(ADB_AUTH_PADDING);
        return cipher.doFinal(token);
    }

    /** ADB peer-info record contains Base64(524-byte adb_rsa_pubkey) + comment + NUL. */
    public byte[] getAdbPublicKey() {
        return AdbPublicKeyEncoder.encode(publicKey, identity);
    }

}
