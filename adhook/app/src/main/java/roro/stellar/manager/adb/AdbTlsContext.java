package roro.stellar.manager.adb;

import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.cert.X509Certificate;

import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;

/** Builds the dedicated TLSv1.3 context for the ADB SPAKE2 pairing protocol. */
public final class AdbTlsContext {
    private AdbTlsContext() { }

    public static SSLContext create(KeyPair identity) throws GeneralSecurityException {
        if (identity == null || !(identity.getPublic() instanceof java.security.interfaces.RSAPublicKey)) {
            throw new GeneralSecurityException("ADB TLS identity must contain an RSA key pair");
        }
        X509Certificate certificate = AdbClientCertificate.create(
                (java.security.interfaces.RSAPublicKey) identity.getPublic(), identity.getPrivate());
        SSLContext context = SSLContext.getInstance("TLSv1.3");
        context.init(
                new KeyManager[]{new AdbTlsKeyManager(certificate, identity.getPrivate())},
                new TrustManager[]{new AdbPairingTrustManager()},
                new java.security.SecureRandom());
        return context;
    }
}
