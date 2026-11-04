package roro.stellar.manager.adb;

import java.net.Socket;
import java.security.Principal;
import java.security.PrivateKey;
import java.security.cert.X509Certificate;

import javax.net.ssl.SSLEngine;
import javax.net.ssl.X509ExtendedKeyManager;

/** Supplies the single client RSA identity used by ADB wireless pairing. */
final class AdbTlsKeyManager extends X509ExtendedKeyManager {
    static final String ALIAS = "key";
    private final X509Certificate certificate;
    private final PrivateKey privateKey;
    private final X509Certificate[] chain;

    AdbTlsKeyManager(X509Certificate certificate, PrivateKey privateKey) {
        if (certificate == null || privateKey == null) {
            throw new IllegalArgumentException("ADB TLS identity is incomplete");
        }
        this.certificate = certificate;
        this.privateKey = privateKey;
        this.chain = new X509Certificate[]{certificate};
    }

    @Override public String[] getClientAliases(String keyType, Principal[] issuers) {
        return "RSA".equalsIgnoreCase(keyType) ? new String[]{ALIAS} : null;
    }

    @Override public String chooseClientAlias(String[] keyTypes, Principal[] issuers,
                                               Socket socket) {
        if (keyTypes == null) return null;
        for (String keyType : keyTypes) {
            if ("RSA".equalsIgnoreCase(keyType)) return ALIAS;
        }
        return null;
    }

    @Override public String chooseEngineClientAlias(String[] keyTypes, Principal[] issuers,
                                                     SSLEngine engine) {
        return chooseClientAlias(keyTypes, issuers, null);
    }

    @Override public X509Certificate[] getCertificateChain(String alias) {
        return ALIAS.equals(alias) ? chain.clone() : null;
    }

    @Override public PrivateKey getPrivateKey(String alias) {
        return ALIAS.equals(alias) ? privateKey : null;
    }

    @Override public String[] getServerAliases(String keyType, Principal[] issuers) {
        return null;
    }

    @Override public String chooseServerAlias(String keyType, Principal[] issuers, Socket socket) {
        return null;
    }

    @Override public String chooseEngineServerAlias(String keyType, Principal[] issuers,
                                                     SSLEngine engine) {
        return null;
    }
}
