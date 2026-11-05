package roro.stellar.manager.adb;

import java.math.BigInteger;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAPublicKey;
import java.util.Date;

import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x500.RDN;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

/**
 * Original Stellar ADB client certificate shape, using the same BouncyCastle
 * builder as the 9.9.60 implementation: v3, serial 1, empty issuer/subject,
 * epoch start, 2048 expiry and SHA256withRSA.
 */
public final class AdbClientCertificate {
    private static final long NOT_AFTER_MILLIS = 2461449600000L;

    private AdbClientCertificate() { }

    public static X509Certificate create(RSAPublicKey publicKey, PrivateKey privateKey)
            throws GeneralSecurityException, CertificateException {
        if (publicKey == null || privateKey == null) {
            throw new IllegalArgumentException("ADB certificate keys are required");
        }
        try {
            X500Name emptyName = new X500Name(new RDN[0]);
            JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(
                    emptyName, BigInteger.ONE, new Date(0L),
                    new Date(NOT_AFTER_MILLIS), emptyName, publicKey);
            BouncyCastleProvider provider = new BouncyCastleProvider();
            ContentSigner signer = new JcaContentSignerBuilder("SHA256withRSA")
                    .setProvider(provider)
                    .build(privateKey);
            X509Certificate certificate = new JcaX509CertificateConverter()
                    .setProvider(provider)
                    .getCertificate(builder.build(signer));
            certificate.checkValidity(new Date());
            certificate.verify(publicKey);
            return certificate;
        } catch (Exception failure) {
            if (failure instanceof GeneralSecurityException) {
                throw (GeneralSecurityException) failure;
            }
            throw new GeneralSecurityException(
                    "Unable to create the original Stellar ADB TLS client certificate", failure);
        }
    }
}
