package roro.stellar.manager.adb;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.RSAPublicKey;
import java.security.cert.CertificateException;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;

/**
 * Builds the original Stellar ADB client certificate shape without relying on
 * hidden platform internals: v3, serial 1, empty issuer/subject, 1970..2048
 * validity and SHA256withRSA signature.
 */
public final class AdbClientCertificate {
    private static final byte[] SIGNATURE_ALGORITHM = sequence(
            oid(new byte[]{0x2a, (byte) 0x86, 0x48, (byte) 0x86, (byte) 0xf7, 0x0d, 0x01, 0x01, 0x0b}),
            tagged(0x05, new byte[0]));

    private AdbClientCertificate() { }

    public static X509Certificate create(RSAPublicKey publicKey, PrivateKey privateKey)
            throws GeneralSecurityException, CertificateException {
        if (publicKey == null || privateKey == null) {
            throw new IllegalArgumentException("ADB certificate keys are required");
        }

        byte[] version = tagged(0xa0, integer(BigInteger.valueOf(2)));
        byte[] serial = integer(BigInteger.ONE);
        byte[] emptyName = sequence();
        byte[] validity = sequence(
                tagged(0x17, "700101000000Z".getBytes(StandardCharsets.US_ASCII)),
                tagged(0x17, "480101000000Z".getBytes(StandardCharsets.US_ASCII)));
        byte[] subjectPublicKeyInfo = publicKey.getEncoded();
        if (subjectPublicKeyInfo == null || subjectPublicKeyInfo.length == 0) {
            throw new GeneralSecurityException("RSA SubjectPublicKeyInfo is unavailable");
        }

        byte[] tbsCertificate = sequence(version, serial, SIGNATURE_ALGORITHM,
                emptyName, validity, emptyName, subjectPublicKeyInfo);
        Signature signer = Signature.getInstance("SHA256withRSA");
        signer.initSign(privateKey);
        signer.update(tbsCertificate);
        byte[] signature = signer.sign();

        byte[] signatureBits = new byte[signature.length + 1];
        signatureBits[0] = 0; // DER BIT STRING unused-bit count.
        System.arraycopy(signature, 0, signatureBits, 1, signature.length);
        byte[] encodedCertificate = sequence(
                tbsCertificate,
                SIGNATURE_ALGORITHM,
                tagged(0x03, signatureBits));

        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        X509Certificate certificate = (X509Certificate) factory.generateCertificate(
                new ByteArrayInputStream(encodedCertificate));
        certificate.verify(publicKey);
        certificate.checkValidity(new java.util.Date());
        return certificate;
    }

    private static byte[] integer(BigInteger value) {
        return tagged(0x02, value.toByteArray());
    }

    private static byte[] oid(byte[] body) {
        return tagged(0x06, body);
    }

    private static byte[] sequence(byte[]... values) {
        ByteArrayOutputStream body = new ByteArrayOutputStream();
        try {
            for (byte[] value : values) body.write(value);
        } catch (IOException impossible) {
            throw new AssertionError(impossible);
        }
        return tagged(0x30, body.toByteArray());
    }

    private static byte[] tagged(int tag, byte[] body) {
        ByteArrayOutputStream output = new ByteArrayOutputStream(body.length + 8);
        output.write(tag);
        writeLength(output, body.length);
        try {
            output.write(body);
        } catch (IOException impossible) {
            throw new AssertionError(impossible);
        }
        return output.toByteArray();
    }

    private static void writeLength(ByteArrayOutputStream output, int length) {
        if (length < 0x80) {
            output.write(length);
            return;
        }
        int bytes = 0;
        int value = length;
        while (value != 0) {
            bytes++;
            value >>>= 8;
        }
        output.write(0x80 | bytes);
        for (int shift = (bytes - 1) * 8; shift >= 0; shift -= 8) {
            output.write((length >>> shift) & 0xff);
        }
    }
}
