package roro.stellar.manager.adb;

import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.interfaces.RSAKey;

import javax.crypto.Cipher;

/**
 * ADB AUTH uses a 20-byte SHA-1 prehash token and an RSASSA-PKCS1-v1_5
 * signature. The prehash is already computed by adbd; do not hash it again.
 */
final class AdbAuthSignature {
    private static final int MODULUS_BYTES = 256;
    private static final int TOKEN_BYTES = 20;
    private static final byte[] SHA1_DIGEST_INFO_PREFIX = new byte[]{
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e,
            0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14
    };

    private AdbAuthSignature() { }

    static byte[] encodePrehashedSha1(byte[] token) {
        if (token == null || token.length != TOKEN_BYTES) {
            throw new IllegalArgumentException("ADB AUTH challenge must be exactly 20 bytes");
        }
        int digestInfoLength = SHA1_DIGEST_INFO_PREFIX.length + TOKEN_BYTES;
        int paddingLength = MODULUS_BYTES - 3 - digestInfoLength;
        if (paddingLength < 8) {
            throw new IllegalStateException("RSA modulus is too small for SHA-1 PKCS#1 v1.5");
        }
        byte[] encoded = new byte[MODULUS_BYTES];
        encoded[0] = 0;
        encoded[1] = 1;
        java.util.Arrays.fill(encoded, 2, 2 + paddingLength, (byte) 0xff);
        int separator = 2 + paddingLength;
        encoded[separator] = 0;
        System.arraycopy(SHA1_DIGEST_INFO_PREFIX, 0,
                encoded, separator + 1, SHA1_DIGEST_INFO_PREFIX.length);
        System.arraycopy(token, 0, encoded,
                separator + 1 + SHA1_DIGEST_INFO_PREFIX.length, TOKEN_BYTES);
        return encoded;
    }

    static byte[] sign(PrivateKey privateKey, byte[] token) throws GeneralSecurityException {
        if (privateKey == null || !(privateKey instanceof RSAKey)) {
            throw new GeneralSecurityException("ADB AUTH requires an RSA private key");
        }
        if (((RSAKey) privateKey).getModulus().bitLength() != 2048) {
            throw new GeneralSecurityException("ADB AUTH requires an RSA-2048 host key");
        }
        byte[] encoded = encodePrehashedSha1(token);
        try {
            // Raw RSA over an explicitly built EMSA-PKCS1-v1_5 block. The
            // Android RSA provider performs the private-key operation.
            Cipher cipher = Cipher.getInstance("RSA/ECB/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, privateKey);
            return cipher.doFinal(encoded);
        } finally {
            java.util.Arrays.fill(encoded, (byte) 0);
        }
    }
}
