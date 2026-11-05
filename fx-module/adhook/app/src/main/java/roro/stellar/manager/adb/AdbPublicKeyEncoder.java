package roro.stellar.manager.adb;

import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.interfaces.RSAPublicKey;
import java.util.Base64;

/** Encodes the 524-byte Android adb_rsa_pubkey structure and the Stellar comment suffix. */
public final class AdbPublicKeyEncoder {
    public static final int ANDROID_PUBKEY_MODULUS_SIZE = 256;
    public static final int ANDROID_PUBKEY_MODULUS_SIZE_WORDS = 64;
    public static final int RSA_PUBLIC_KEY_SIZE = 0x20c;
    private static final BigInteger WORD_BASE = BigInteger.ONE.shiftLeft(32);
    private static final BigInteger RR_BASE = BigInteger.ONE.shiftLeft(2048);

    private AdbPublicKeyEncoder() { }

    public static byte[] encode(RSAPublicKey key, String comment) {
        if (key == null) throw new IllegalArgumentException("RSA public key is required");
        if (comment == null || comment.length() > 256
                || comment.indexOf('\u0000') >= 0 || comment.indexOf('\n') >= 0
                || comment.indexOf('\r') >= 0) {
            throw new IllegalArgumentException("ADB key comment is invalid");
        }
        BigInteger modulus = key.getModulus();
        BigInteger exponent = key.getPublicExponent();
        if (modulus == null || modulus.signum() <= 0
                || modulus.bitLength() != ANDROID_PUBKEY_MODULUS_SIZE * 8
                || exponent == null || exponent.signum() <= 0
                || exponent.bitLength() > 31) {
            throw new IllegalArgumentException("ADB requires a 2048-bit RSA key and a positive 32-bit exponent");
        }

        int n0inv = modulus.mod(WORD_BASE).modInverse(WORD_BASE).negate().intValue();
        BigInteger rr = RR_BASE.modPow(BigInteger.TWO, modulus);
        ByteBuffer structure = ByteBuffer.allocate(RSA_PUBLIC_KEY_SIZE)
                .order(ByteOrder.LITTLE_ENDIAN);
        structure.putInt(ANDROID_PUBKEY_MODULUS_SIZE_WORDS);
        structure.putInt(n0inv);
        putWords(structure, modulus);
        putWords(structure, rr);
        structure.putInt(exponent.intValue());

        byte[] encoded = Base64.getEncoder().encode(structure.array());
        byte[] suffix = (" " + comment + "\u0000").getBytes(StandardCharsets.UTF_8);
        byte[] result = new byte[encoded.length + suffix.length];
        System.arraycopy(encoded, 0, result, 0, encoded.length);
        System.arraycopy(suffix, 0, result, encoded.length, suffix.length);
        return result;
    }

    /** The PeerInfo payload is the public-key line without its own NUL; the 8192-byte
     * PeerInfo zero padding supplies the single required terminator. */
    public static byte[] encodeLine(RSAPublicKey key, String comment) {
        byte[] terminated = encode(key, comment);
        try {
            return java.util.Arrays.copyOf(terminated, terminated.length - 1);
        } finally {
            java.util.Arrays.fill(terminated, (byte) 0);
        }
    }

    private static void putWords(ByteBuffer output, BigInteger value) {
        BigInteger remaining = value;
        for (int i = 0; i < ANDROID_PUBKEY_MODULUS_SIZE_WORDS; i++) {
            BigInteger[] parts = remaining.divideAndRemainder(WORD_BASE);
            output.putInt(parts[1].intValue());
            remaining = parts[0];
        }
        if (remaining.signum() != 0) {
            throw new IllegalArgumentException("RSA integer exceeds the fixed ADB key width");
        }
    }
}
