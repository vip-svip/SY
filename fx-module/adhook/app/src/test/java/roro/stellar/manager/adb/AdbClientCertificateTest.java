package roro.stellar.manager.adb;

import org.junit.Test;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAKeyGenParameterSpec;
import java.security.cert.X509Certificate;

import javax.net.ssl.SSLContext;

import static org.junit.Assert.*;

public final class AdbClientCertificateTest {
    private KeyPair createRsaIdentity() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(new RSAKeyGenParameterSpec(2048, RSAKeyGenParameterSpec.F4));
        return generator.generateKeyPair();
    }

    @Test
    public void createsOriginalEmptyNameAdbCertificateAndVerifiesItsSignature() throws Exception {
        KeyPair identity = createRsaIdentity();
        X509Certificate certificate = AdbClientCertificate.create(
                (RSAPublicKey) identity.getPublic(), identity.getPrivate());

        certificate.verify(identity.getPublic());
        assertEquals(BigInteger.ONE, certificate.getSerialNumber());
        assertEquals(0L, certificate.getNotBefore().getTime());
        assertEquals(2461449600000L, certificate.getNotAfter().getTime());
        assertArrayEquals(identity.getPublic().getEncoded(), certificate.getPublicKey().getEncoded());
        assertTrue(certificate.getSigAlgName().equalsIgnoreCase("SHA256withRSA"));
    }

    @Test
    public void tlsContextUsesTls13AndTheOriginalYoulongClientAlias() throws Exception {
        KeyPair identity = createRsaIdentity();
        X509Certificate certificate = AdbClientCertificate.create(
                (RSAPublicKey) identity.getPublic(), identity.getPrivate());
        SSLContext context = AdbTlsContext.create(identity);
        assertEquals("TLSv1.3", context.getProtocol());

        AdbTlsKeyManager keyManager = new AdbTlsKeyManager(
                certificate, identity.getPrivate());
        assertEquals("youlong", keyManager.chooseClientAlias(new String[]{"RSA"}, null, null));
        assertEquals(1, keyManager.getCertificateChain("youlong").length);
        assertEquals(identity.getPrivate(), keyManager.getPrivateKey("youlong"));
        assertNull(keyManager.chooseServerAlias("RSA", null, null));
    }
}
