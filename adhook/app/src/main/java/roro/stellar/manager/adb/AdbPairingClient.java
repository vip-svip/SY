package roro.stellar.manager.adb;

import java.io.Closeable;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * Android 11+ ADB wireless-debugging pairing client, ported from Stellar 9.9.60.
 *
 * The caller supplies the pairing port discovered for _adb-tls-pairing._tcp.
 * This class performs only the TLS + SPAKE2 + PeerInfo exchange. It does not
 * scan for services or start the follow-up _adb-tls-connect._tcp discovery.
 *
 * Run start() on a dedicated worker/service: socket operations block until
 * their bounded connect/read timeouts fire.
 */
public final class AdbPairingClient implements Closeable {
    public static final String TLS_PAIRING_SERVICE = "_adb-tls-pairing._tcp";
    public static final String TLS_CONNECT_SERVICE = "_adb-tls-connect._tcp";
    private static final int CONNECT_TIMEOUT_MS = 10_000;
    private static final int READ_TIMEOUT_MS = 30_000;
    private static final int EXPORTER_LENGTH = 64;
    private static final String EXPORTER_LABEL = "adb-label\0";
    private static final int MAX_PAIRING_FRAME = 0x4000;

    private final String host;
    private final int port;
    private final String pairingCode;
    private final AdbKey key;
    private final AtomicBoolean started = new AtomicBoolean(false);
    private final AtomicBoolean closed = new AtomicBoolean(false);

    private Socket rawSocket;
    private SSLSocket tlsSocket;
    private DataInputStream input;
    private DataOutputStream output;
    private PairingContext pairingContext;

    public AdbPairingClient(String host, int port, String pairingCode, AdbKey key) {
        this.host = validateHost(host);
        if (port < 1 || port > 65535) throw new IllegalArgumentException("Invalid ADB pairing port");
        if (pairingCode == null || !pairingCode.matches("[0-9]{6}")) {
            throw new IllegalArgumentException("ADB pairing code must contain exactly six digits");
        }
        if (key == null) throw new IllegalArgumentException("ADB host key is null");
        this.port = port;
        this.pairingCode = pairingCode;
        this.key = key;
    }

    private static String validateHost(String value) {
        if (value == null || value.isEmpty() || value.length() > 253
                || value.indexOf('/') >= 0 || value.indexOf('\\0') >= 0
                || value.indexOf(' ') >= 0) {
            throw new IllegalArgumentException("Invalid ADB pairing host");
        }
        return value;
    }

    /**
     * Performs the original TLS/SPAKE2/PeerInfo exchange.
     *
     * @return true only after the peer has sent a valid encrypted PeerInfo record
     */
    public synchronized boolean start() throws IOException {
        if (!started.compareAndSet(false, true)) {
            throw new IllegalStateException("ADB pairing client can only be started once");
        }
        if (closed.get()) throw new IOException("ADB pairing client is already closed");

        try {
            setupTlsConnection();
            setupSpake2Context();
            if (!exchangeSpake2Messages()) {
                throw new PairingException("ADB SPAKE2 message exchange was rejected");
            }
            if (!exchangePeerInfo()) {
                throw new PairingException("ADB encrypted peer-info exchange was rejected");
            }
            return true;
        } catch (IOException | RuntimeException failure) {
            closeQuietly();
            throw failure;
        } finally {
            // Do not retain the UI-supplied pairing code after the TLS exporter
            // and SPAKE2 context have been initialized.
            // String itself cannot be zeroed; all derived byte arrays are wiped.
        }
    }

    private void setupTlsConnection() throws IOException {
        rawSocket = new Socket();
        rawSocket.setTcpNoDelay(true);
        rawSocket.setSoTimeout(READ_TIMEOUT_MS);
        rawSocket.connect(new InetSocketAddress(host, port), CONNECT_TIMEOUT_MS);

        SSLSocketFactory factory = key.getSslContext().getSocketFactory();
        tlsSocket = (SSLSocket) factory.createSocket(rawSocket, host, port, true);
        tlsSocket.setSoTimeout(READ_TIMEOUT_MS);
        tlsSocket.setEnabledProtocols(new String[]{"TLSv1.3"});
        tlsSocket.startHandshake();

        input = new DataInputStream(tlsSocket.getInputStream());
        output = new DataOutputStream(tlsSocket.getOutputStream());
    }

    private void setupSpake2Context() throws IOException {
        byte[] code = pairingCode.getBytes(StandardCharsets.UTF_8);
        byte[] exporter = null;
        byte[] secret = null;
        try {
            exporter = exportKeyingMaterial(tlsSocket, EXPORTER_LABEL, EXPORTER_LENGTH);
            if (exporter == null || exporter.length != EXPORTER_LENGTH) {
                throw new IOException("Conscrypt returned an invalid ADB TLS exporter");
            }
            secret = new byte[code.length + exporter.length];
            // Original Stellar order: UTF-8 pairing code followed by TLS exporter bytes.
            System.arraycopy(code, 0, secret, 0, code.length);
            System.arraycopy(exporter, 0, secret, code.length, exporter.length);
            pairingContext = PairingContext.create(secret);
            if (pairingContext == null) {
                throw new IOException("Original libadb SPAKE2 JNI context is unavailable");
            }
        } finally {
            Arrays.fill(code, (byte) 0);
            if (exporter != null) Arrays.fill(exporter, (byte) 0);
            if (secret != null) Arrays.fill(secret, (byte) 0);
        }
    }

    private static byte[] exportKeyingMaterial(SSLSocket socket, String label, int length)
            throws IOException {
        try {
            Class<?> conscrypt = Class.forName("com.android.org.conscrypt.Conscrypt");
            Method method = conscrypt.getMethod(
                    "exportKeyingMaterial", SSLSocket.class, String.class, byte[].class, int.class);
            Object result = method.invoke(null, socket, label, null, length);
            if (!(result instanceof byte[])) {
                throw new IOException("Conscrypt TLS exporter returned no byte array");
            }
            return (byte[]) result;
        } catch (InvocationTargetException wrapped) {
            Throwable cause = wrapped.getCause();
            throw new IOException("Conscrypt could not export the ADB pairing TLS key material", cause);
        } catch (ReflectiveOperationException | SecurityException failure) {
            throw new IOException(
                    "This Android build does not expose the Conscrypt TLS exporter required by ADB pairing",
                    failure);
        }
    }

    private boolean exchangeSpake2Messages() throws IOException {
        byte[] localMessage = pairingContext.getMsg();
        byte[] remoteMessage = null;
        try {
            writeFrame(PairingPacketHeader.Type.SPAKE2_MSG, localMessage);
            PairingPacketHeader header = readHeader();
            if (header.getType() != PairingPacketHeader.Type.SPAKE2_MSG.getValue()) {
                throw new PairingException("Expected an ADB SPAKE2 message frame");
            }
            remoteMessage = readPayload(header.getPayload());
            return pairingContext.initCipher(remoteMessage);
        } finally {
            Arrays.fill(localMessage, (byte) 0);
            if (remoteMessage != null) Arrays.fill(remoteMessage, (byte) 0);
        }
    }

    private boolean exchangePeerInfo() throws IOException {
        byte[] publicKeyLine = key.getAdbPublicKey();
        byte[] plainRecord = null;
        byte[] encryptedRecord = null;
        byte[] remoteEncrypted = null;
        byte[] remotePlain = null;
        try {
            ByteBuffer peerBuffer = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH)
                    .order(ByteOrder.BIG_ENDIAN);
            new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), publicKeyLine)
                    .writeTo(peerBuffer);
            plainRecord = peerBuffer.array();
            encryptedRecord = pairingContext.encrypt(plainRecord);
            if (encryptedRecord == null || encryptedRecord.length == 0
                    || encryptedRecord.length > MAX_PAIRING_FRAME) {
                throw new PairingException("libadb returned an invalid encrypted PeerInfo record");
            }
            writeFrame(PairingPacketHeader.Type.PEER_INFO, encryptedRecord);

            PairingPacketHeader header = readHeader();
            if (header.getType() != PairingPacketHeader.Type.PEER_INFO.getValue()) {
                throw new PairingException("Expected an ADB PeerInfo frame");
            }
            remoteEncrypted = readPayload(header.getPayload());
            remotePlain = pairingContext.decrypt(remoteEncrypted);
            if (remotePlain == null || remotePlain.length != PeerInfo.RECORD_LENGTH) {
                throw new PairingException("ADB peer-info authentication failed (invalid pairing code)");
            }
            ByteBuffer remoteBuffer = ByteBuffer.wrap(remotePlain).order(ByteOrder.BIG_ENDIAN);
            PeerInfo.readFrom(remoteBuffer);
            return true;
        } finally {
            Arrays.fill(publicKeyLine, (byte) 0);
            if (plainRecord != null) Arrays.fill(plainRecord, (byte) 0);
            if (encryptedRecord != null) Arrays.fill(encryptedRecord, (byte) 0);
            if (remoteEncrypted != null) Arrays.fill(remoteEncrypted, (byte) 0);
            if (remotePlain != null) Arrays.fill(remotePlain, (byte) 0);
        }
    }

    private void writeFrame(PairingPacketHeader.Type type, byte[] payload) throws IOException {
        if (payload == null || payload.length < PairingPacketHeader.MIN_PAYLOAD
                || payload.length > MAX_PAIRING_FRAME) {
            throw new PairingException("ADB pairing frame payload is outside the permitted range");
        }
        ByteBuffer headerBuffer = ByteBuffer.allocate(PairingPacketHeader.SIZE_BYTES)
                .order(ByteOrder.BIG_ENDIAN);
        new PairingPacketHeader((byte) 1, type.getValue(), payload.length).writeTo(headerBuffer);
        output.write(headerBuffer.array());
        output.write(payload);
        output.flush();
    }

    private PairingPacketHeader readHeader() throws IOException {
        byte[] encoded = new byte[PairingPacketHeader.SIZE_BYTES];
        input.readFully(encoded);
        try {
            PairingPacketHeader header = PairingPacketHeader.readFrom(ByteBuffer.wrap(encoded));
            if (header == null) throw new PairingException("ADB pairing frame header is invalid");
            if (header.getPayload() > MAX_PAIRING_FRAME) {
                throw new PairingException("ADB pairing frame exceeds the size limit");
            }
            return header;
        } finally {
            Arrays.fill(encoded, (byte) 0);
        }
    }

    private byte[] readPayload(int length) throws IOException {
        if (length < PairingPacketHeader.MIN_PAYLOAD || length > MAX_PAIRING_FRAME) {
            throw new PairingException("ADB pairing payload length is invalid");
        }
        byte[] payload = new byte[length];
        try {
            input.readFully(payload);
            return payload;
        } catch (IOException failure) {
            Arrays.fill(payload, (byte) 0);
            throw failure;
        }
    }

    @Override
    public synchronized void close() {
        if (!closed.compareAndSet(false, true)) return;
        closeQuietly();
    }

    private void closeQuietly() {
        PairingContext context = pairingContext;
        pairingContext = null;
        if (context != null) {
            try { context.destroy(); } catch (RuntimeException | LinkageError ignored) { }
        }
        DataInputStream in = input;
        input = null;
        if (in != null) {
            try { in.close(); } catch (IOException ignored) { }
        }
        DataOutputStream out = output;
        output = null;
        if (out != null) {
            try { out.close(); } catch (IOException ignored) { }
        }
        SSLSocket tls = tlsSocket;
        tlsSocket = null;
        if (tls != null) {
            try { tls.close(); } catch (IOException ignored) { }
        }
        Socket raw = rawSocket;
        rawSocket = null;
        if (raw != null) {
            try { raw.close(); } catch (IOException ignored) { }
        }
    }

    public static final class PairingException extends IOException {
        public PairingException(String message) {
            super(message);
        }
    }
}
