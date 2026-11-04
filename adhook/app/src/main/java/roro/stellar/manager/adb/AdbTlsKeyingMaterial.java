package roro.stellar.manager.adb;

import android.net.ssl.SSLSockets;
import android.os.Build;

import java.util.Arrays;

import javax.net.ssl.SSLException;
import javax.net.ssl.SSLSocket;

/** Exports the RFC 5705 material bound to the ADB TLS 1.3 pairing handshake. */
public final class AdbTlsKeyingMaterial {
    public static final String LABEL = "adb-label" + (char) 0;
    public static final int LENGTH_BYTES = 64;

    private AdbTlsKeyingMaterial() { }

    public static byte[] export(SSLSocket socket) throws SSLException {
        if (socket == null || socket.isClosed()) {
            throw new SSLException("ADB TLS socket is not connected");
        }
        // SSLSockets.exportKeyingMaterial is a public SDK API from Android 12
        // (API 31); avoid reflecting into com.android.org.conscrypt hidden APIs.
        if (Build.VERSION.SDK_INT < 31) {
            throw new UnsupportedOperationException(
                    "Automatic ADB pairing requires Android 12/API 31 or newer");
        }
        byte[] material = SSLSockets.exportKeyingMaterial(
                socket, LABEL, null, LENGTH_BYTES);
        if (material == null || material.length != LENGTH_BYTES) {
            if (material != null) Arrays.fill(material, (byte) 0);
            throw new SSLException("TLS exporter did not return the required 64-byte ADB material");
        }
        return material;
    }
}
