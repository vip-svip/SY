package roro.stellar.manager.adb;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.io.IOException;
import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.GeneralSecurityException;
import java.security.Key;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.RSAKeyGenParameterSpec;
import java.util.Arrays;
import java.util.Date;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509ExtendedKeyManager;
import javax.net.ssl.X509TrustManager;
import java.net.Socket;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;
import javax.net.ssl.SSLEngine;

import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x500.RDN;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

/**
 * Stable host identity for the original Stellar ADB wireless pairing protocol.
 *
 * Storage deliberately matches the original 9.9.60 contract:
 * device-protected SharedPreferences "settings", entry "adbkey", AES/GCM
 * encrypted PKCS#8, AndroidKeyStore alias "_adbkey_encryption_key_", and
 * a 16-byte AAD block beginning with the UTF-8 bytes "adbkey".
 *
 * Existing encrypted identity material is never silently replaced on an
 * authentication/decryption failure: that could orphan a device-side trust.
 */
public final class AdbKey {
    private static final String PREFS_NAME = "settings";
    private static final String PREF_KEY = "adbkey";
    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
    private static final String ENCRYPTION_KEY_ALIAS = "_adbkey_encryption_key_";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int AES_KEY_SIZE_BITS = 256;
    private static final int GCM_IV_BYTES = 12;
    private static final int GCM_TAG_BITS = 128;
    private static final int RSA_BITS = 2048;
    private static final int RSA_WORDS = 64;
    private static final int ADB_PUBLIC_KEY_BYTES = 524;
    private static final long CERT_NOT_AFTER_MS = 2461449600000L; // 2048-01-01T00:00:00Z
    private static final byte[] AAD = createAad();

    private final RSAPrivateKey privateKey;
    private final RSAPublicKey publicKey;
    private final X509Certificate certificate;
    private final SSLContext sslContext;
    private final String identity;

    private AdbKey(SharedPreferences preferences, String identity)
            throws GeneralSecurityException, IOException {
        if (preferences == null) throw new IllegalArgumentException("ADB preferences are null");
        if (identity == null || identity.isEmpty() || identity.length() > 64
                || !identity.matches("[A-Za-z0-9_.@-]+")) {
            throw new IllegalArgumentException("ADB host identity is invalid");
        }
        this.identity = identity;
        SecretKey encryptionKey = getOrCreateEncryptionKey();
        this.privateKey = getOrCreatePrivateKey(preferences, encryptionKey);
        KeyFactoryPair pair = deriveKeyPair(this.privateKey);
        this.publicKey = pair.publicKey;
        this.certificate = createCertificate(this.privateKey, this.publicKey);
        this.sslContext = createSslContext();
    }

    public static AdbKey getOrCreate(Context context)
            throws GeneralSecurityException, IOException {
        if (context == null) throw new IllegalArgumentException("Context is null");
        Context storage = context.createDeviceProtectedStorageContext();
        SharedPreferences preferences = storage.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        return new AdbKey(preferences, "youlong");
    }

    /** Public constructor for tests and controlled migration tooling. */
    static AdbKey getOrCreate(SharedPreferences preferences, String identity)
            throws GeneralSecurityException, IOException {
        return new AdbKey(preferences, identity);
    }

    private static byte[] createAad() {
        byte[] aad = new byte[16];
        byte[] marker = "adbkey".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        System.arraycopy(marker, 0, aad, 0, marker.length);
        Arrays.fill(marker, (byte) 0);
        return aad;
    }

    private static SecretKey getOrCreateEncryptionKey() throws GeneralSecurityException, IOException {
        KeyStore store = KeyStore.getInstance(ANDROID_KEYSTORE);
        try {
            store.load(null);
        } catch (IOException failure) {
            throw failure;
        } catch (Exception failure) {
            throw new GeneralSecurityException("Unable to load AndroidKeyStore", failure);
        }
        Key existing;
        try {
            existing = store.getKey(ENCRYPTION_KEY_ALIAS, null);
        } catch (Exception failure) {
            throw new GeneralSecurityException("Unable to read the existing Stellar ADB encryption key", failure);
        }
        if (existing != null) {
            if (!(existing instanceof SecretKey)) {
                throw new GeneralSecurityException("Stored Stellar ADB encryption key has the wrong type");
            }
            return (SecretKey) existing;
        }

        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE);
        KeyGenParameterSpec spec = new KeyGenParameterSpec.Builder(
                ENCRYPTION_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(AES_KEY_SIZE_BITS)
                .setRandomizedEncryptionRequired(true)
                .build();
        generator.init(spec);
        return generator.generateKey();
    }

    private static RSAPrivateKey getOrCreatePrivateKey(
            SharedPreferences preferences, SecretKey encryptionKey)
            throws GeneralSecurityException, IOException {
        if (preferences.contains(PREF_KEY)) {
            String encoded = preferences.getString(PREF_KEY, null);
            if (encoded == null || encoded.isEmpty()) {
                throw new GeneralSecurityException("Stored Stellar ADB key record is empty");
            }
            byte[] record;
            try {
                record = Base64.decode(encoded, Base64.NO_WRAP);
            } catch (IllegalArgumentException malformed) {
                throw new GeneralSecurityException("Stored Stellar ADB key record is malformed", malformed);
            }
            byte[] pkcs8 = null;
            try {
                pkcs8 = decryptPrivateKey(record, encryptionKey);
                Key key = java.security.KeyFactory.getInstance("RSA")
                        .generatePrivate(new PKCS8EncodedKeySpec(pkcs8));
                if (!(key instanceof RSAPrivateKey)
                        || ((RSAPrivateKey) key).getModulus().bitLength() != RSA_BITS) {
                    throw new GeneralSecurityException("Stored Stellar ADB key is not a 2048-bit RSA key");
                }
                return (RSAPrivateKey) key;
            } finally {
                Arrays.fill(record, (byte) 0);
                if (pkcs8 != null) Arrays.fill(pkcs8, (byte) 0);
            }
        }

        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(new RSAKeyGenParameterSpec(RSA_BITS, RSAKeyGenParameterSpec.F4),
                new SecureRandom());
        KeyPair generated = generator.generateKeyPair();
        if (!(generated.getPrivate() instanceof RSAPrivateKey)) {
            throw new GeneralSecurityException("RSA provider returned an incompatible private key");
        }
        byte[] pkcs8 = generated.getPrivate().getEncoded();
        if (pkcs8 == null || pkcs8.length == 0 || pkcs8.length > 16 * 1024) {
            throw new GeneralSecurityException("Generated Stellar ADB private key encoding is invalid");
        }
        byte[] record = null;
        try {
            record = encryptPrivateKey(pkcs8, encryptionKey);
            String value = Base64.encodeToString(record, Base64.NO_WRAP);
            if (!preferences.edit().putString(PREF_KEY, value).commit()) {
                throw new IOException("Unable to persist the generated Stellar ADB host identity");
            }
        } finally {
            Arrays.fill(pkcs8, (byte) 0);
            if (record != null) Arrays.fill(record, (byte) 0);
        }
        return (RSAPrivateKey) generated.getPrivate();
    }

    private static byte[] encryptPrivateKey(byte[] clear, SecretKey key)
            throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.ENCRYPT_MODE, key);
        cipher.updateAAD(AAD);
        byte[] encrypted = cipher.doFinal(clear);
        byte[] iv = cipher.getIV();
        if (iv == null || iv.length != GCM_IV_BYTES) {
            Arrays.fill(encrypted, (byte) 0);
            throw new GeneralSecurityException("AndroidKeyStore returned an invalid AES-GCM IV");
        }
        byte[] result = new byte[iv.length + encrypted.length];
        System.arraycopy(iv, 0, result, 0, iv.length);
        System.arraycopy(encrypted, 0, result, iv.length, encrypted.length);
        Arrays.fill(encrypted, (byte) 0);
        return result;
    }

    private static byte[] decryptPrivateKey(byte[] record, SecretKey key)
            throws GeneralSecurityException {
        if (record == null || record.length < GCM_IV_BYTES + 16 || record.length > 32 * 1024) {
            throw new GeneralSecurityException("Stored Stellar ADB key record has an invalid length");
        }
        byte[] iv = Arrays.copyOfRange(record, 0, GCM_IV_BYTES);
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, iv));
            cipher.updateAAD(AAD);
            return cipher.doFinal(record, GCM_IV_BYTES, record.length - GCM_IV_BYTES);
        } finally {
            Arrays.fill(iv, (byte) 0);
        }
    }

    private static KeyPairPair deriveKeyPair(RSAPrivateKey privateKey)
            throws GeneralSecurityException {
        java.security.spec.RSAPublicKeySpec publicSpec = new java.security.spec.RSAPublicKeySpec(
                privateKey.getModulus(), RSAKeyGenParameterSpec.F4);
        java.security.PublicKey key = java.security.KeyFactory.getInstance("RSA").generatePublic(publicSpec);
        if (!(key instanceof RSAPublicKey)) {
            throw new GeneralSecurityException("Unable to derive Stellar ADB RSA public key");
        }
        return new KeyPairPair(privateKey, (RSAPublicKey) key);
    }

    private static final class KeyPairPair {
        final RSAPublicKey publicKey;
        KeyPairPair(RSAPrivateKey ignored, RSAPublicKey publicKey) {
            this.publicKey = publicKey;
        }
    }

    private static X509Certificate createCertificate(RSAPrivateKey privateKey, RSAPublicKey publicKey)
            throws GeneralSecurityException {
        try {
            X500Name emptyName = new X500Name(new RDN[0]);
            JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(
                    emptyName,
                    BigInteger.ONE,
                    new Date(0L),
                    new Date(CERT_NOT_AFTER_MS),
                    emptyName,
                    publicKey);
            org.bouncycastle.jce.provider.BouncyCastleProvider provider =
                    new org.bouncycastle.jce.provider.BouncyCastleProvider();
            ContentSigner signer = new JcaContentSignerBuilder("SHA256withRSA")
                    .setProvider(provider)
                    .build(privateKey);
            X509CertificateHolder holder = builder.build(signer);
            X509Certificate cert = new JcaX509CertificateConverter()
                    .setProvider(provider)
                    .getCertificate(holder);
            cert.checkValidity(new Date());
            cert.verify(publicKey);
            return cert;
        } catch (Exception failure) {
            throw new GeneralSecurityException("Unable to create the original Stellar ADB TLS certificate", failure);
        }
    }

    private SSLContext createSslContext() throws GeneralSecurityException {
        SSLContext context = SSLContext.getInstance("TLSv1.3");
        context.init(new KeyManager[]{new ADBKeyManager(privateKey, certificate)},
                new TrustManager[]{new PairingTrustManager()}, new SecureRandom());
        return context;
    }

    public SSLContext getSslContext() {
        return sslContext;
    }

    public RSAPrivateKey getPrivateKey() {
        return privateKey;
    }

    public RSAPublicKey getPublicKey() {
        return publicKey;
    }

    public X509Certificate getCertificate() {
        return certificate;
    }

    public byte[] getAdbPublicKey() {
        byte[] binary = encodeAdbPublicKey(publicKey);
        String text = Base64.encodeToString(binary, Base64.NO_WRAP) + " " + identity;
        byte[] line = (text + "\0").getBytes(java.nio.charset.StandardCharsets.UTF_8);
        Arrays.fill(binary, (byte) 0);
        return line;
    }

    /** Original Android ADB 524-byte RSA public-key structure. */
    static byte[] encodeAdbPublicKey(RSAPublicKey publicKey) {
        BigInteger modulus = publicKey.getModulus();
        BigInteger wordBase = BigInteger.ONE.shiftLeft(32);
        BigInteger n0inv = modulus.mod(wordBase).modInverse(wordBase).negate();
        BigInteger rr = BigInteger.ONE.shiftLeft(RSA_WORDS * 64).mod(modulus);
        ByteBuffer buffer = ByteBuffer.allocate(ADB_PUBLIC_KEY_BYTES).order(ByteOrder.LITTLE_ENDIAN);
        buffer.putInt(RSA_WORDS);
        buffer.putInt(n0inv.intValue());
        putLittleEndianWords(buffer, modulus);
        putLittleEndianWords(buffer, rr);
        buffer.putInt(publicKey.getPublicExponent().intValue());
        if (buffer.position() != ADB_PUBLIC_KEY_BYTES) {
            throw new IllegalStateException("ADB RSA public-key encoder produced an invalid size");
        }
        return buffer.array();
    }

    private static void putLittleEndianWords(ByteBuffer output, BigInteger value) {
        BigInteger wordBase = BigInteger.ONE.shiftLeft(32);
        BigInteger remaining = value;
        for (int i = 0; i < RSA_WORDS; i++) {
            BigInteger[] parts = remaining.divideAndRemainder(wordBase);
            output.putInt(parts[1].intValue());
            remaining = parts[0];
        }
        if (remaining.signum() != 0) {
            throw new IllegalArgumentException("RSA integer exceeds the ADB 2048-bit field");
        }
    }

    /** ADB AUTH uses an RSA PKCS#1 v1.5 SHA-1 signature over the challenge. */
    public byte[] sign(byte[] token) throws GeneralSecurityException {
        if (token == null || token.length != 20) {
            throw new GeneralSecurityException("ADB AUTH challenge must be exactly 20 bytes");
        }
        Signature signature = Signature.getInstance("SHA1withRSA");
        signature.initSign(privateKey, new SecureRandom());
        signature.update(token);
        return signature.sign();
    }

    public static final class ADBKeyManager extends X509ExtendedKeyManager {
        private static final String ALIAS = "youlong";
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
        @Override public String chooseEngineClientAlias(String[] keyTypes, Principal[] issuers, SSLEngine engine) {
            if (keyTypes == null) return null;
            for (String keyType : keyTypes) if ("RSA".equalsIgnoreCase(keyType)) return ALIAS;
            return null;
        }
        @Override public String chooseEngineServerAlias(String keyType, Principal[] issuers, SSLEngine engine) {
            return null;
        }
    }

    /** Pairing authenticates the peer with SPAKE2 after TLS, as in the original client. */
    private static final class PairingTrustManager implements X509TrustManager {
        @Override public void checkClientTrusted(X509Certificate[] chain, String authType) { }
        @Override public void checkServerTrusted(X509Certificate[] chain, String authType) { }
        @Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
    }
}
