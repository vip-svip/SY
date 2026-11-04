package roro.stellar.manager.adb;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.SecureRandom;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.RSAKeyGenParameterSpec;
import java.security.spec.RSAPublicKeySpec;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Original Stellar key format:
 * AndroidKeyStore AES/GCM, 12-byte IV prefix, 128-bit tag, and 16-byte "adbkey" AAD.
 */
public final class AdbPrivateKeyVault {
    private static final String RSA = "RSA";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int AES_GCM_IV_BYTES = 12;
    private static final int AES_GCM_TAG_BITS = 128;
    private static final int MIN_ENCRYPTED_BYTES = AES_GCM_IV_BYTES + 16;
    private static final int MAX_ENCRYPTED_BYTES = 8192;
    private static final int PRIVATE_KEY_BITS = 2048;
    private static final byte[] AAD = createAad();

    private final AdbKeyStore keyStore;
    private final SecretKey encryptionKey;
    private final SecureRandom random;

    public AdbPrivateKeyVault(AdbKeyStore keyStore, SecretKey encryptionKey) {
        this(keyStore, encryptionKey, new SecureRandom());
    }

    AdbPrivateKeyVault(AdbKeyStore keyStore, SecretKey encryptionKey, SecureRandom random) {
        if (keyStore == null || encryptionKey == null || random == null) {
            throw new IllegalArgumentException("ADB key vault dependencies are required");
        }
        this.keyStore = keyStore;
        this.encryptionKey = encryptionKey;
        this.random = random;
    }

    public synchronized KeyPair loadOrCreate() throws GeneralSecurityException {
        byte[] stored = keyStore.get();
        if (stored != null) {
            try {
                RSAPrivateKey privateKey = decodePrivateKey(decrypt(stored));
                KeyFactory factory = KeyFactory.getInstance(RSA);
                RSAPublicKey publicKey = (RSAPublicKey) factory.generatePublic(
                        new RSAPublicKeySpec(privateKey.getModulus(), RSAKeyGenParameterSpec.F4));
                if (privateKey.getModulus().bitLength() == PRIVATE_KEY_BITS) {
                    return new KeyPair(publicKey, privateKey);
                }
            } catch (GeneralSecurityException | RuntimeException invalidStoredKey) {
                // Match the original behavior: an unreadable encrypted key is regenerated.
            } finally {
                Arrays.fill(stored, (byte) 0);
            }
        }

        KeyPairGenerator generator = KeyPairGenerator.getInstance(RSA);
        generator.initialize(new RSAKeyGenParameterSpec(PRIVATE_KEY_BITS, RSAKeyGenParameterSpec.F4), random);
        KeyPair pair = generator.generateKeyPair();
        byte[] encoded = pair.getPrivate().getEncoded();
        try {
            byte[] encrypted = encrypt(encoded);
            try {
                keyStore.put(encrypted);
            } finally {
                Arrays.fill(encrypted, (byte) 0);
            }
        } finally {
            Arrays.fill(encoded, (byte) 0);
        }
        return pair;
    }

    public byte[] encrypt(byte[] plaintext) throws GeneralSecurityException {
        if (plaintext == null || plaintext.length == 0 || plaintext.length > MAX_ENCRYPTED_BYTES - 28) {
            throw new GeneralSecurityException("ADB private key payload is outside the allowed size");
        }
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey, random);
        cipher.updateAAD(AAD);
        byte[] ciphertext = cipher.doFinal(plaintext);
        byte[] iv = cipher.getIV();
        if (iv == null || iv.length != AES_GCM_IV_BYTES) {
            Arrays.fill(ciphertext, (byte) 0);
            throw new GeneralSecurityException("AndroidKeyStore returned an invalid AES-GCM IV");
        }
        byte[] result = new byte[iv.length + ciphertext.length];
        System.arraycopy(iv, 0, result, 0, iv.length);
        System.arraycopy(ciphertext, 0, result, iv.length, ciphertext.length);
        Arrays.fill(ciphertext, (byte) 0);
        return result;
    }

    public byte[] decrypt(byte[] encrypted) throws GeneralSecurityException {
        if (encrypted == null || encrypted.length < MIN_ENCRYPTED_BYTES
                || encrypted.length > MAX_ENCRYPTED_BYTES) {
            throw new GeneralSecurityException("Encrypted ADB private key is malformed");
        }
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        GCMParameterSpec parameters = new GCMParameterSpec(
                AES_GCM_TAG_BITS, encrypted, 0, AES_GCM_IV_BYTES);
        cipher.init(Cipher.DECRYPT_MODE, encryptionKey, parameters);
        cipher.updateAAD(AAD);
        return cipher.doFinal(encrypted, AES_GCM_IV_BYTES,
                encrypted.length - AES_GCM_IV_BYTES);
    }

    public static byte[] getAadForTesting() {
        return AAD.clone();
    }

    private static byte[] createAad() {
        byte[] result = new byte[16];
        byte[] prefix = "adbkey".getBytes(StandardCharsets.UTF_8);
        System.arraycopy(prefix, 0, result, 0, prefix.length);
        return result;
    }

    private static RSAPrivateKey decodePrivateKey(byte[] encoded) throws GeneralSecurityException {
        if (encoded == null || encoded.length == 0 || encoded.length > MAX_ENCRYPTED_BYTES) {
            throw new GeneralSecurityException("Decrypted ADB private key is malformed");
        }
        try {
            return (RSAPrivateKey) KeyFactory.getInstance(RSA)
                    .generatePrivate(new PKCS8EncodedKeySpec(encoded));
        } finally {
            Arrays.fill(encoded, (byte) 0);
        }
    }
}
