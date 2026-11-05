package roro.stellar.manager.adb;

import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;

import javax.net.ssl.X509ExtendedTrustManager;

/**
 * Mirrors the original ADB pairing trust-manager behavior: the pairing peer's
 * certificate is not a pre-provisioned PKI identity. Peer authenticity is
 * bound later by the ADB SPAKE2 exchange over TLS-exported keying material.
 *
 * This manager must only be used by AdbTlsContext for the ADB pairing protocol,
 * never by general-purpose HTTPS or other FX network clients.
 */
final class AdbPairingTrustManager extends X509ExtendedTrustManager {
    @Override public void checkClientTrusted(X509Certificate[] chain, String authType)
            throws CertificateException { }

    @Override public void checkServerTrusted(X509Certificate[] chain, String authType)
            throws CertificateException { }

    @Override public void checkClientTrusted(X509Certificate[] chain, String authType,
                                               java.net.Socket socket)
            throws CertificateException { }

    @Override public void checkServerTrusted(X509Certificate[] chain, String authType,
                                               java.net.Socket socket)
            throws CertificateException { }

    @Override public void checkClientTrusted(X509Certificate[] chain, String authType,
                                               javax.net.ssl.SSLEngine engine)
            throws CertificateException { }

    @Override public void checkServerTrusted(X509Certificate[] chain, String authType,
                                               javax.net.ssl.SSLEngine engine)
            throws CertificateException { }

    @Override public X509Certificate[] getAcceptedIssuers() {
        return new X509Certificate[0];
    }
}
