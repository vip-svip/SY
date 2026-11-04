#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in AdbKeyStore.java AdbPrivateKeyVault.java AdbPublicKeyEncoder.java AndroidAdbEncryptionKey.java PreferenceAdbKeyStore.java AdbKey.java AdbAuthSignature.java AdbPairingClient.java; do
    [ -s "$SRC/$file" ] || fail "Stellar ADB identity source missing: $file"
done

# Compile the Android-independent vault and ADB RSA public-key encoder with the
# host JDK. Exercise key persistence, AES-GCM authentication, and exact wire math.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-stellar-adb-identity.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/classes" "$TMP/test/roro/stellar/manager/adb"
cat > "$TMP/test/roro/stellar/manager/adb/AdbIdentitySmoke.java" <<'JAVA'
package roro.stellar.manager.adb;

import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPublicKey;
import java.util.Arrays;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

public final class AdbIdentitySmoke {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static final class MemoryStore implements AdbKeyStore {
        private byte[] value;
        @Override public synchronized byte[] get() {
            return value == null ? null : value.clone();
        }
        @Override public synchronized void put(byte[] next) {
            if (value != null) Arrays.fill(value, (byte) 0);
            value = next.clone();
        }
    }

    private static BigInteger readLittleEndian(ByteBuffer input, int words) {
        BigInteger result = BigInteger.ZERO;
        for (int i = 0; i < words; i++) {
            long word = input.getInt() & 0xffffffffL;
            result = result.add(BigInteger.valueOf(word).shiftLeft(i * 32));
        }
        return result;
    }

    public static void main(String[] args) throws Exception {
        byte[] aad = AdbPrivateKeyVault.getAadForTesting();
        byte[] expectedAad = new byte[16];
        System.arraycopy("adbkey".getBytes(StandardCharsets.UTF_8), 0, expectedAad, 0, 6);
        check(Arrays.equals(aad, expectedAad), "ADB private-key AES-GCM AAD does not match original 16-byte adbkey block");

        SecretKey aes = new SecretKeySpec(new byte[32], "AES");
        MemoryStore store = new MemoryStore();
        AdbPrivateKeyVault vault = new AdbPrivateKeyVault(store, aes);
        KeyPair generated = vault.loadOrCreate();
        byte[] authToken = new byte[20];
        for (int i = 0; i < authToken.length; i++) authToken[i] = (byte) (i * 7 + 3);
        byte[] encodedAuth = AdbAuthSignature.encodePrehashedSha1(authToken);
        check(encodedAuth.length == 256, "ADB AUTH EMSA block must be exactly 256 bytes for RSA-2048");
        check(encodedAuth[0] == 0 && encodedAuth[1] == 1, "ADB AUTH block must start with PKCS#1 v1.5 type-1 padding");
        for (int i = 2; i < 220; i++) check(encodedAuth[i] == (byte) 0xff, "ADB AUTH FF padding is malformed");
        check(encodedAuth[220] == 0, "ADB AUTH DigestInfo separator is missing");
        byte[] sha1Prefix = new byte[]{0x30,0x21,0x30,0x09,0x06,0x05,0x2b,0x0e,0x03,0x02,0x1a,0x05,0x00,0x04,0x14};
        check(Arrays.equals(sha1Prefix, Arrays.copyOfRange(encodedAuth, 221, 236)),
                "ADB AUTH SHA-1 DigestInfo DER prefix is malformed");
        check(Arrays.equals(authToken, Arrays.copyOfRange(encodedAuth, 236, 256)),
                "ADB AUTH prehash must be appended unchanged (never hashed a second time)");
        byte[] authSignature = AdbAuthSignature.sign(generated.getPrivate(), authToken);
        check(authSignature.length == 256, "ADB AUTH RSA signature length must be 256 bytes");
        javax.crypto.Cipher publicOperation = javax.crypto.Cipher.getInstance("RSA/ECB/NoPadding");
        publicOperation.init(javax.crypto.Cipher.DECRYPT_MODE, generated.getPublic());
        byte[] verifiedAuthBlock = publicOperation.doFinal(authSignature);
        check(Arrays.equals(verifiedAuthBlock, encodedAuth),
                "ADB AUTH signature did not verify to the exact PKCS#1 v1.5 SHA-1 prehash block");
        Arrays.fill(authSignature, (byte) 0);
        Arrays.fill(verifiedAuthBlock, (byte) 0);
        Arrays.fill(encodedAuth, (byte) 0);
        boolean invalidTokenRejected = false;
        try { AdbAuthSignature.sign(generated.getPrivate(), new byte[19]); }
        catch (IllegalArgumentException expected) { invalidTokenRejected = true; }
        check(invalidTokenRejected, "ADB AUTH must reject non-20-byte challenge tokens");
        check(generated.getPrivate() instanceof java.security.interfaces.RSAPrivateKey,
                "ADB vault did not generate an RSA private key");
        check(((RSAPublicKey) generated.getPublic()).getModulus().bitLength() == 2048,
                "ADB vault RSA modulus is not 2048 bits");
        byte[] persisted = store.get();
        check(persisted != null && persisted.length > 28 && persisted.length < 8192,
                "ADB vault did not persist a bounded IV+ciphertext record");
        byte[] decrypted = vault.decrypt(persisted);
        check(decrypted.length > 0, "AES-GCM decrypt returned an empty PKCS#8 key");
        Arrays.fill(decrypted, (byte) 0);
        KeyPair restored = vault.loadOrCreate();
        check(generated.getPrivate().equals(restored.getPrivate()),
                "ADB key load did not preserve the same private identity");
        check(generated.getPublic().equals(restored.getPublic()),
                "ADB key load did not preserve the same public identity");

        byte[] corrupted = store.get();
        corrupted[corrupted.length - 1] ^= 0x40;
        store.put(corrupted);
        Arrays.fill(corrupted, (byte) 0);
        boolean corruptRejected = false;
        try {
            vault.loadOrCreate();
        } catch (Exception expected) {
            corruptRejected = true;
        }
        check(corruptRejected, "tampered existing ADB key must fail closed instead of silently rotating identity");

        KeyPairGenerator rsa = KeyPairGenerator.getInstance("RSA");
        rsa.initialize(2048);
        RSAPublicKey publicKey = (RSAPublicKey) rsa.generateKeyPair().getPublic();
        byte[] line = AdbPublicKeyEncoder.encode(publicKey, "youlong");
        int nul = line.length - 1;
        check(line[nul] == 0, "ADB public-key suffix must be NUL terminated");
        String keyText = new String(line, 0, nul, StandardCharsets.UTF_8);
        check(keyText.endsWith(" youlong"), "ADB public-key comment must match original Stellar identity");
        String base64 = keyText.substring(0, keyText.indexOf(' '));
        byte[] raw = java.util.Base64.getDecoder().decode(base64);
        check(raw.length == 524, "ADB RSA public-key binary must be exactly 524 bytes");
        ByteBuffer wire = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN);
        check(wire.getInt() == 64, "ADB modulus word count must be 64");
        int n0inv = wire.getInt();
        BigInteger modulus = readLittleEndian(wire, 64);
        BigInteger rr = readLittleEndian(wire, 64);
        long exponent = wire.getInt() & 0xffffffffL;
        check(modulus.equals(publicKey.getModulus()), "ADB RSA modulus little-endian words changed");
        check(exponent == publicKey.getPublicExponent().longValue(), "ADB RSA exponent changed");
        BigInteger wordBase = BigInteger.ONE.shiftLeft(32);
        check(modulus.mod(wordBase).multiply(BigInteger.valueOf(n0inv & 0xffffffffL))
                        .mod(wordBase).equals(wordBase.subtract(BigInteger.ONE)),
                "ADB RSA n0inv does not satisfy -N^-1 mod 2^32");
        check(rr.equals(BigInteger.ONE.shiftLeft(4096).mod(modulus)),
                "ADB RSA rr does not equal 2^4096 mod N");

        boolean invalidCommentRejected = false;
        try { AdbPublicKeyEncoder.encode(publicKey, "bad\ncomment"); }
        catch (IllegalArgumentException expected) { invalidCommentRejected = true; }
        check(invalidCommentRejected, "ADB public-key comment must reject control characters");
        System.out.println("PASS: Stellar AES-GCM identity persistence, tamper refusal, and original 524-byte ADB RSA encoding");
    }
}
JAVA

javac -d "$TMP/classes" \
    "$SRC/AdbKeyStore.java" \
    "$SRC/AdbPrivateKeyVault.java" \
    "$SRC/AdbPublicKeyEncoder.java" \
    "$SRC/AdbAuthSignature.java" \
    "$TMP/test/roro/stellar/manager/adb/AdbIdentitySmoke.java" \
    || fail "Android-independent ADB vault/encoder classes do not compile on the host JDK"
java -cp "$TMP/classes" roro.stellar.manager.adb.AdbIdentitySmoke \
    || fail "ADB vault/public-key encoder regression failed"

# Cross-check the Android wrapper still composes the tested helpers and preserves
# the original TLS certificate, AUTH signer, and device-protected preference store.
grep -Fq 'new PreferenceAdbKeyStore(preferences)' "$SRC/AdbKey.java" || fail "AdbKey no longer uses the original preference store"
grep -Fq 'AndroidAdbEncryptionKey.getOrCreate()' "$SRC/AdbKey.java" || fail "AdbKey no longer uses the AndroidKeyStore AES key"
grep -Fq 'new AdbPrivateKeyVault(' "$SRC/AdbKey.java" || fail "AdbKey does not use the encrypted PKCS#8 vault"
grep -Fq 'AdbPublicKeyEncoder.encode(publicKey, identity)' "$SRC/AdbKey.java" || fail "AdbKey does not use the tested ADB RSA wire encoder"
grep -Fq 'AdbAuthSignature.sign(privateKey, token)' "$SRC/AdbKey.java" || fail "ADB AUTH does not delegate to the tested prehashed SHA-1 signer"
grep -Fq 'SHA1_DIGEST_INFO_PREFIX' "$SRC/AdbAuthSignature.java" || fail "ADB AUTH is missing the SHA-1 DigestInfo DER prefix"
grep -Fq 'paddingLength = MODULUS_BYTES - 3 - digestInfoLength' "$SRC/AdbAuthSignature.java" || fail "ADB AUTH PKCS#1 v1.5 padding length is not derived from RSA-2048 block size"
grep -Fq 'Cipher.getInstance("RSA/ECB/NoPadding")' "$SRC/AdbAuthSignature.java" || fail "ADB AUTH raw RSA primitive is missing"
! grep -Fq 'ADB_AUTH_PADDING' "$SRC/AdbKey.java" || fail "obsolete malformed AUTH padding remains in AdbKey"
grep -Fq 'SSLContext.getInstance("TLSv1.3")' "$SRC/AdbKey.java" || fail "ADB TLS context is not pinned to TLS 1.3"

grep -Fq 'settings' "$SRC/AdbKey.java" || fail "original device-protected preference file name changed"
grep -Fq 'adbkey' "$SRC/PreferenceAdbKeyStore.java" || fail "original ADB preference key changed"
grep -Fq '_adbkey_encryption_key_' "$SRC/AndroidAdbEncryptionKey.java" || fail "original AndroidKeyStore alias changed"
grep -Fq 'exportKeyingMaterial' "$SRC/AdbPairingClient.java" || fail "TLS exporter is missing from the SPAKE2 client"
grep -Fq 'adb-label\\0' "$SRC/AdbPairingClient.java" || fail "original ADB TLS exporter label changed"
grep -Fq 'new String[]{"TLSv1.3"}' "$SRC/AdbPairingClient.java" || fail "ADB pairing socket is not restricted to TLS 1.3"
grep -Fq 'PairingContext.create(secret)' "$SRC/AdbPairingClient.java" || fail "TLS exporter secret is not passed to original libadb SPAKE2 context"
grep -Fq 'PairingPacketHeader.Type.SPAKE2_MSG' "$SRC/AdbPairingClient.java" || fail "SPAKE2 wire exchange is missing"
grep -Fq 'PairingPacketHeader.Type.PEER_INFO' "$SRC/AdbPairingClient.java" || fail "encrypted PeerInfo wire exchange is missing"
grep -Fq 'new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), publicKeyLine)' "$SRC/AdbPairingClient.java" || fail "ADB RSA public key is not included in the PeerInfo exchange"
grep -Fq 'CONNECT_TIMEOUT_MS = 10_000' "$SRC/AdbPairingClient.java" || fail "ADB pairing connect timeout is missing"
grep -Fq 'READ_TIMEOUT_MS = 30_000' "$SRC/AdbPairingClient.java" || fail "ADB pairing read timeout is missing"

echo "PASS: original Stellar ADB identity, encrypted key persistence, TLS client identity and SPAKE2/PeerInfo source contract"
