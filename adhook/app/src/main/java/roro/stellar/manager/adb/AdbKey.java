package roro.stellar.manager.adb;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.cert.X509Certificate;
import java.util.Date;

import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509ExtendedKeyManager;
import javax.net.ssl.X509TrustManager;
import javax.crypto.Cipher;
import java.net.Socket;
import javax.net.ssl.SSLEngine;

import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x500.RDN;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

/**
 * Stable host identity for the original Stellar ADB wireless-pairing protocol.
 *
 * Uses the original device-protected "settings" preference store, encrypted
 * "adbkey" PKCS#8 record, AndroidKeyStore AES alias, and ADB RSA public-key
 * wire format. The ADB TLS peer certificate is self-signed; SPAKE2 pairing
 * authenticates the peer after the TLS key exporter is derived.
 */
public final class AdbKey {
    private static final long CERT_NOT_AFTER_MS = 2461449600000L; // 2048-01-01T00:00:00Z
    private static final String IDENTITY = "youlong";
    private static final byte[] ADB_AUTH_PADDING = createAdbAuthPadding();

    private static byte[] createAdbAuthPadding() {
        byte[] padding = new byte[236];
        padding[0] = 0;
        padding[1] = 1;
        java.util.Arrays.fill(padding, 2, padding.length, (byte) 0xff);
        return padding;
    }

    private final RSAPrivateKey privateKey;
    private final RSAPublicKey publicKey;
    private final X509Certificate certificate;
    private final SSLContext sslContext;
    private final String identity;

    private AdbKey(Context context, String identity)
            throws GeneralSecurityException, IOException {
        if (context == null) throw new IllegalArgumentException("Context is null");
        Context storage = context.createDeviceProtectedStorageContext();
        SharedPreferences preferences = storage.getSharedPreferences("settings", Context.MODE_PRIVATE);
        this.identity = validateIdentity(identity);
        this.privateKey = loadPrivateKey(preferences);
        this.publicKey = derivePublicKey(privateKey);
        this.certificate = createCertificate(privateKey, publicKey);
        this.sslContext = createSslContext();
    }

    private AdbKey(SharedPreferences preferences, String identity)
            throws GeneralSecurityException {
        if (preferences == null) throw new IllegalArgumentException("ADB preferences are null");
        this.identity = validateIdentity(identity);
        this.privateKey = loadPrivateKey(preferences);
        this.publicKey = derivePublicKey(privateKey);
        this.certificate = createCertificate(privateKey, publicKey);
        this.sslContext = createSslContext();
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

    private static RSAPrivateKey loadPrivateKey(SharedPreferences preferences)
            throws GeneralSecurityException {
        AdbPrivateKeyVault vault = new AdbPrivateKeyVault(
                new PreferenceAdbKeyStore(preferences),
                AndroidAdbEncryptionKey.getOrCreate());
        java.security.KeyPair pair = vault.loadOrCreate();
        if (!(pair.getPrivate() instanceof RSAPrivateKey)
                || !(pair.getPublic() instanceof RSAPublicKey)) {
            throw new GeneralSecurityException("ADB vault returned an incompatible RSA key pair");
        }
        return (RSAPrivateKey) pair.getPrivate();
    }

    private static RSAPublicKey derivePublicKey(RSAPrivateKey privateKey)
            throws GeneralSecurityException {
        java.security.spec.RSAPublicKeySpec spec = new java.security.spec.RSAPublicKeySpec(
                privateKey.getModulus(), java.security.spec.RSAKeyGenParameterSpec.F4);
        java.security.PublicKey key = java.security.KeyFactory.getInstance("RSA").generatePublic(spec);
        if (!(key instanceof RSAPublicKey)) {
            throw new GeneralSecurityException("Unable to derive Stellar ADB RSA public key");
        }
        return (RSAPublicKey) key;
    }

    private static X509Certificate createCertificate(RSAPrivateKey privateKey, RSAPublicKey publicKey)
            throws GeneralSecurityException {
        try {
            X500Name emptyName = new X500Name(new RDN[0]);
            JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(
                    emptyName, java.math.BigInteger.ONE, new Date(0L),
                    new Date(CERT_NOT_AFTER_MS), emptyName, publicKey);
            org.bouncycastle.jce.provider.BouncyCastleProvider provider =
                    new org.bouncycastle.jce.provider.BouncyCastleProvider();
            ContentSigner signer = new JcaContentSignerBuilder("SHA256withRSA")
                    .setProvider(provider)
                    .build(privateKey);
            X509Certificate cert = new JcaX509CertificateConverter()
                    .setProvider(provider)
                    .getCertificate(builder.build(signer));
            cert.checkValidity(new Date());
            cert.verify(publicKey);
            return cert;
        } catch (Exception failure) {
            throw new GeneralSecurityException("Unable to create the Stellar ADB TLS certificate", failure);
        }
    }

    private SSLContext createSslContext() throws GeneralSecurityException {
        SSLContext context = SSLContext.getInstance("TLSv1.3");
        context.init(new KeyManager[]{new ADBKeyManager(privateKey, certificate)},
                new TrustManager[]{new PairingTrustManager()}, new SecureRandom());
        return context;
    }

    public SSLContext getSslContext() { return sslContext; }
    public RSAPrivateKey getPrivateKey() { return privateKey; }
    public RSAPublicKey getPublicKey() { return publicKey; }
    public X509Certificate getCertificate() { return certificate; }

    /**
     * Original ADB AUTH signature: raw RSA private operation over the 236-byte
     * 00 01 FF... block followed by the 20-byte daemon challenge. This is not
     * SHA1withRSA DigestInfo encoding; adb expects the raw AUTH padding block.
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

    public static final class ADBKeyManager extends X509ExtendedKeyManager {
        private static final String ALIAS = IDENTITY;
        private final RSAPrivateKey privateKey;
        private final X509Certificate certificate;

        ADBKeyManager(RSAPrivateKey privateKey, X509Certificate certificate) {
            this.privateKey = privateKey;
            this.certificate = certificate;
        }

        @Override public String[] getClientAliases(String keyType, Principal[] issuers) {
            return "RSA".equalsIgnoreCase(keyType) ? new String[]{ALIAS} : null;
        }
        @Override public String chooseClientAlias(String[] keyTypes, Principal[] issuers, Socket socket) {
            if (keyTypes == null) return null;
            for (String keyType : keyTypes) if ("RSA".equalsIgnoreCase(keyType)) return ALIAS;
            return null;
        }
        @Override public String[] getServerAliases(String keyType, Principal[] issuers) {
            return null;
        }
        @Override public String chooseServerAlias(String keyType, Principal[] issuers, Socket socket) {
            return null;
        }
        @Override public X509Certificate[] getCertificateChain(String alias) {
            return ALIAS.equals(alias) ? new X509Certificate[]{certificate} : null;
        }
        @Override public PrivateKey getPrivateKey(String alias) {
            return ALIAS.equals(alias) ? privateKey : null;
        }
        @Override public String chooseEngineClientAlias(
                String[] keyTypes, Principal[] issuers, SSLEngine engine) {
            if (keyTypes == null) return null;
            for (String keyType : keyTypes) if ("RSA".equalsIgnoreCase(keyType)) return ALIAS;
            return null;
        }
        @Override public String chooseEngineServerAlias(
                String keyType, Principal[] issuers, SSLEngine engine) {
            return null;
        }
    }

    /**
     * ADB's pairing port uses a self-signed TLS identity; the subsequent SPAKE2
     * exchange authenticates possession of the six-digit pairing secret.
     */
    private static final class PairingTrustManager implements X509TrustManager {
        @Override public void checkClientTrusted(X509Certificate[] chain, String authType) { }
        @Override public void checkServerTrusted(X509Certificate[] chain, String authType) { }
        @Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
    }
}
