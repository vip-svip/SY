#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb"
VAULT="$SRC/AdbPrivateKeyVault.java"
STORE="$SRC/AdbKeyStore.java"
ENCODER="$SRC/AdbPublicKeyEncoder.java"
ANDROID_KEY="$SRC/AndroidAdbEncryptionKey.java"
CERT="$SRC/AdbClientCertificate.java"
TLS_MANAGER="$SRC/AdbTlsKeyManager.java"
TRUST_MANAGER="$SRC/AdbPairingTrustManager.java"
TLS_CONTEXT="$SRC/AdbTlsContext.java"
TLS_EXPORTER="$SRC/AdbTlsKeyingMaterial.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$VAULT" "$STORE" "$ENCODER" "$ANDROID_KEY" "$CERT" "$TLS_MANAGER" "$TRUST_MANAGER" "$TLS_CONTEXT" "$TLS_EXPORTER"; do
    [ -s "$file" ] || fail "missing Stellar key component: $file"
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-stellar-key.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/src/roro/stellar/manager/adb" "$TMP/classes"
cat > "$TMP/src/roro/stellar/manager/adb/AdbKeyVaultSmoke.java" <<'JAVA'
package roro.stellar.manager.adb;

import java.math.BigInteger;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPrivateKey;
import java.security.interfaces.RSAPublicKey;
import java.util.Arrays;

import javax.crypto.AEADBadTagException;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;

public final class AdbKeyVaultSmoke {
    private static final class MemoryStore implements AdbKeyStore {
        private byte[] saved;
        @Override public synchronized byte[] get() {
            return saved == null ? null : saved.clone();
        }
        @Override public synchronized void put(byte[] value) {
            saved = value.clone();
        }
    }
    private static void check(boolean value, String reason) {
        if (!value) throw new AssertionError(reason);
    }
    private static BigInteger readWords(ByteBuffer input) {
        long[] words = new long[64];
        for (int i = 0; i < words.length; i++) words[i] = input.getInt() & 0xffffffffL;
        BigInteger result = BigInteger.ZERO;
        for (int i = words.length - 1; i >= 0; i--) {
            result = result.shiftLeft(32).add(BigInteger.valueOf(words[i]));
        }
        return result;
    }

    public static void main(String[] args) throws Exception {
        KeyGenerator aesGenerator = KeyGenerator.getInstance("AES");
        aesGenerator.init(256);
        SecretKey aes = aesGenerator.generateKey();
        MemoryStore store = new MemoryStore();
        AdbPrivateKeyVault first = new AdbPrivateKeyVault(store, aes);

        byte[] aad = AdbPrivateKeyVault.getAadForTesting();
        check(aad.length == 16, "original AAD must be exactly 16 bytes");
        check(Arrays.equals(Arrays.copyOf(aad, 6), "adbkey".getBytes(StandardCharsets.UTF_8)),
                "original AAD prefix changed");
        for (int i = 6; i < aad.length; i++) check(aad[i] == 0, "original AAD zero padding changed");

        byte[] plaintext = "Stellar private-key envelope regression".getBytes(StandardCharsets.UTF_8);
        byte[] ciphertextA = first.encrypt(plaintext);
        byte[] ciphertextB = first.encrypt(plaintext);
        check(ciphertextA.length == plaintext.length + 28, "AES-GCM envelope must be 12-byte IV + 16-byte tag");
        check(!Arrays.equals(Arrays.copyOf(ciphertextA, 12), Arrays.copyOf(ciphertextB, 12)),
                "AES-GCM IV must be freshly generated for each encryption");
        check(Arrays.equals(plaintext, first.decrypt(ciphertextA)), "AES-GCM envelope round-trip failed");
        byte[] tampered = ciphertextA.clone();
        tampered[tampered.length - 1] ^= 1;
        try {
            first.decrypt(tampered);
            throw new AssertionError("tampered AES-GCM ciphertext was accepted");
        } catch (AEADBadTagException expected) {
            // Authenticated encryption must reject modified ciphertext.
        }

        KeyPair persisted = first.loadOrCreate();
        check(((RSAPrivateKey) persisted.getPrivate()).getModulus().bitLength() == 2048,
                "generated ADB private key must be RSA-2048");
        byte[] persistedEnvelope = store.get();
        check(persistedEnvelope != null && persistedEnvelope.length > 28,
                "encrypted private key was not persisted");
        KeyPair restored = new AdbPrivateKeyVault(store, aes).loadOrCreate();
        check(persisted.getPrivate().equals(restored.getPrivate()),
                "persisted RSA private key was not restored across vault instances");
        check(Arrays.equals(persistedEnvelope, store.get()),
                "restoring an existing RSA key must not rewrite or rotate its encrypted envelope");

        byte[] adb = AdbPublicKeyEncoder.encode((RSAPublicKey) persisted.getPublic(), "youlong");
        int suffixAt = -1;
        for (int i = 0; i < adb.length; i++) {
            if (adb[i] == ' ') { suffixAt = i; break; }
        }
        check(suffixAt > 0, "ADB public key Base64/comment separator missing");
        byte[] suffix = Arrays.copyOfRange(adb, suffixAt + 1, adb.length);
        check(Arrays.equals(suffix, new byte[]{'y','o','u','l','o','n','g',0}),
                "ADB public key suffix must preserve original comment and NUL terminator");
        byte[] binary = java.util.Base64.getDecoder().decode(
                new String(adb, 0, suffixAt, StandardCharsets.US_ASCII));
        check(binary.length == 0x20c, "ADB public key structure must be 524 bytes");
        ByteBuffer fields = ByteBuffer.wrap(binary).order(ByteOrder.LITTLE_ENDIAN);
        check(fields.getInt() == 64, "ADB public key word count must be 64");
        int n0inv = fields.getInt();
        BigInteger modulus = readWords(fields);
        BigInteger rr = readWords(fields);
        long exponent = fields.getInt() & 0xffffffffL;
        RSAPublicKey publicKey = (RSAPublicKey) persisted.getPublic();
        check(modulus.equals(publicKey.getModulus()), "ADB modulus words do not match the persisted RSA key");
        check(exponent == publicKey.getPublicExponent().longValue(), "ADB exponent field changed");
        long lowWord = modulus.and(BigInteger.ONE.shiftLeft(32).subtract(BigInteger.ONE)).longValue();
        long n0product = (lowWord * (n0inv & 0xffffffffL)) & 0xffffffffL;
        check(n0product == 0xffffffffL, "ADB n0inv must be the negative inverse modulo 2^32");
        BigInteger expectedRr = BigInteger.ONE.shiftLeft(2048)
                .modPow(BigInteger.valueOf(2), modulus);
        check(rr.equals(expectedRr), "ADB Montgomery RR field does not match 2^4096 mod n");

        java.security.cert.X509Certificate certificate = AdbClientCertificate.create(
                publicKey, persisted.getPrivate());
        certificate.verify(publicKey);
        check(certificate.getSerialNumber().equals(BigInteger.ONE),
                "ADB client certificate serial must remain one");
        check(certificate.getNotBefore().getTime() == 0L,
                "ADB client certificate validity must start at Unix epoch");
        check(certificate.getNotAfter().getTime() == 2461449600000L,
                "ADB client certificate validity must end at 2048-01-01 UTC");
        check(certificate.getSubjectX500Principal().getName().isEmpty(),
                "ADB client certificate subject must preserve the original empty X500Name");
        javax.net.ssl.SSLContext tls = AdbTlsContext.create(persisted);
        check("TLSv1.3".equals(tls.getProtocol()), "ADB TLS context must use TLSv1.3");

        AdbTlsKeyManager keyManager = new AdbTlsKeyManager(certificate, persisted.getPrivate());
        check("key".equals(keyManager.chooseClientAlias(new String[]{"RSA"}, null, null)),
                "ADB TLS key manager must select the original key alias");
        check(keyManager.getCertificateChain("key").length == 1,
                "ADB TLS key manager must return the original client certificate");
        check(keyManager.getPrivateKey("key").equals(persisted.getPrivate()),
                "ADB TLS key manager must return the persisted RSA private key");
        check(keyManager.chooseServerAlias("RSA", null, null) == null,
                "ADB client key manager must never be selected as a server identity");

        System.out.println("PASS: original adbkey AAD, AES-256/GCM envelope, RSA-2048, ADB public-key encoding, self-signed client certificate and TLSv1.3 key manager");
    }
}
JAVA

javac -d "$TMP/classes" \
    "$STORE" "$VAULT" "$ENCODER" "$CERT" "$TLS_MANAGER" "$TRUST_MANAGER" "$TLS_CONTEXT" \
    "$TMP/src/roro/stellar/manager/adb/AdbKeyVaultSmoke.java" \
    || fail "ADB key vault/public encoder Java sources do not compile on the host"
java -cp "$TMP/classes" roro.stellar.manager.adb.AdbKeyVaultSmoke \
    || fail "ADB key persistence/encryption/public encoding regression failed"

grep -Fq 'getInstance("AndroidKeyStore")' "$ANDROID_KEY" || fail "AES wrapping key must use AndroidKeyStore"
grep -Fq '"_adbkey_encryption_key_"' "$ANDROID_KEY" || fail "original AndroidKeyStore alias changed"
grep -Fq 'KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT' "$ANDROID_KEY" || fail "AndroidKeyStore key purposes changed"
grep -Fq 'KeyProperties.BLOCK_MODE_GCM' "$ANDROID_KEY" || fail "AndroidKeyStore key must use GCM"
grep -Fq 'KeyProperties.ENCRYPTION_PADDING_NONE' "$ANDROID_KEY" || fail "AndroidKeyStore key must use NoPadding"
grep -Fq '"adbkey"' "$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/PreferenceAdbKeyStore.java" || fail "original SharedPreferences key name changed"
grep -Fq 'Build.VERSION.SDK_INT < 31' "$TLS_EXPORTER" || fail "TLS exporter must fail closed below public API 31"
grep -Fq 'SSLSockets.exportKeyingMaterial' "$TLS_EXPORTER" || fail "TLS exporter must use the public Android SDK API"
grep -Fq '"adb-label\\u0000"' "$TLS_EXPORTER" || fail "original TLS exporter label changed"
grep -Fq 'LENGTH_BYTES = 64' "$TLS_EXPORTER" || fail "original TLS exporter length changed"
echo "PASS: AndroidKeyStore alias/purposes, adbkey preference and public SDK TLS exporter contract"
