package roro.stellar.manager.adb;

import java.io.Closeable;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Arrays;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;

/**
 * One-shot ADB TLS/CNXN/AUTH and shell-channel probe for a previously paired endpoint.
 *
 * This deliberately exposes no caller-provided command string. It sends only a fixed,
 * read-only echo marker so the UI can verify that the saved wireless endpoint accepts
 * the paired host identity and that a shell: channel can be opened and closed.
 */
public final class AdbShellProbeClient implements Closeable {
    private static final int ADB_VERSION = 0x01000000;
    private static final int MAX_DATA_BYTES = 1024 * 1024;
    private static final int CONNECT_TIMEOUT_MS = 5000;
    private static final int READ_TIMEOUT_MS = 10000;
    private static final int LOCAL_ID = 1;
    private static final String PROBE_MARKER = "FX_ADB_SHELL_CONNECTED";
    private static final byte[] PROBE_COMMAND =
            AdbWireMessage.nulTerminatedUtf8("shell:echo " + PROBE_MARKER);

    private final String host;
    private final int port;
    private final AdbKey key;
    private volatile boolean closed;
    private volatile Socket rawSocket;
    private volatile SSLSocket tlsSocket;
    private volatile DataInputStream input;
    private volatile DataOutputStream output;

    public AdbShellProbeClient(String host, int port, AdbKey key) {
        if (host == null || host.isEmpty() || host.length() > 253
                || host.indexOf('\0') >= 0 || port < 1 || port > 65535 || key == null) {
            throw new IllegalArgumentException("ADB connect endpoint or host identity is invalid");
        }
        this.host = host;
        this.port = port;
        this.key = key;
    }

    /** Connect, complete TLS plus ADB AUTH, and prove a shell channel using one fixed command. */
    public synchronized String probe() throws IOException, GeneralSecurityException {
        ensureOpen();
        try {
            connectAndAuthenticate();
            ensureOpen();
            return runFixedProbe();
        } catch (IOException | GeneralSecurityException | RuntimeException failure) {
            // Cancellation can race socket construction/registration. Sweep again
            // after the active path unwinds so a late TLS wrapper cannot leak.
            closed = true;
            closeResources();
            throw failure;
        }
    }

    private void connectAndAuthenticate() throws IOException, GeneralSecurityException {
        Socket socket = new Socket();
        rawSocket = socket;
        socket.setTcpNoDelay(true);
        socket.setSoTimeout(READ_TIMEOUT_MS);
        socket.connect(new InetSocketAddress(host, port), CONNECT_TIMEOUT_MS);
        ensureOpen();

        DataInputStream plainInput = new DataInputStream(socket.getInputStream());
        DataOutputStream plainOutput = new DataOutputStream(socket.getOutputStream());
        input = plainInput;
        output = plainOutput;

        // ADB protocol version 1.0.0.1, 4096-byte legacy packet window, host identity.
        write(new AdbWireMessage(AdbWireMessage.CNXN, ADB_VERSION, 4096,
                AdbWireMessage.nulTerminatedUtf8("host::")));

        AdbWireMessage response = read();
        if (response.command != AdbWireMessage.STLS) {
            throw new IOException("Selected connect endpoint did not request ADB TLS (STLS)");
        }

        // ADB wireless-debugging TLS upgrade must be explicitly acknowledged before TLS starts.
        write(new AdbWireMessage(AdbWireMessage.STLS, ADB_VERSION, 0, null));
        SSLContext context = key.getSslContext();
        SSLSocket secure = (SSLSocket) context.getSocketFactory()
                .createSocket(socket, host, port, true);
        tlsSocket = secure;
        secure.setTcpNoDelay(true);
        secure.setSoTimeout(READ_TIMEOUT_MS);
        secure.setEnabledProtocols(new String[]{"TLSv1.3"});
        secure.startHandshake();
        ensureOpen();

        input = new DataInputStream(secure.getInputStream());
        output = new DataOutputStream(secure.getOutputStream());
        response = read();

        if (response.command == AdbWireMessage.AUTH) {
            response = authenticate(response);
        }
        if (response.command != AdbWireMessage.CNXN) {
            throw new IOException("ADB authentication did not complete with CNXN");
        }
    }

    private AdbWireMessage authenticate(AdbWireMessage challenge)
            throws IOException, GeneralSecurityException {
        if (challenge.arg0 != 1 || challenge.data.length != 20) {
            throw new IOException("ADB daemon sent an invalid AUTH token");
        }
        byte[] signature = key.sign(challenge.data);
        try {
            write(new AdbWireMessage(AdbWireMessage.AUTH, 2, 0, signature));
        } finally {
            Arrays.fill(signature, (byte) 0);
        }

        AdbWireMessage response = read();
        if (response.command != AdbWireMessage.CNXN) {
            // The paired RSA identity should already be trusted. Send the exact public key only
            // as the original adb client does when a device asks for the public-key fallback.
            if (response.command != AdbWireMessage.AUTH) {
                throw new IOException("ADB daemon sent an unexpected response after AUTH signature");
            }
            byte[] publicKey = key.getAdbPublicKey();
            try {
                if (publicKey.length == 0 || publicKey.length > 4096) {
                    throw new IOException("ADB host public key is outside the permitted size");
                }
                write(new AdbWireMessage(AdbWireMessage.AUTH, 3, 0, publicKey));
            } finally {
                Arrays.fill(publicKey, (byte) 0);
            }
            response = read();
        }
        return response;
    }

    private String runFixedProbe() throws IOException {
        ensureOpen();
        byte[] service = PROBE_COMMAND.clone();
        try {
            write(new AdbWireMessage(AdbWireMessage.OPEN, LOCAL_ID, 0, service));
        } finally {
            Arrays.fill(service, (byte) 0);
        }

        AdbWireMessage opened = read();
        if (opened.command == AdbWireMessage.CLSE) {
            throw new IOException("Android refused the fixed ADB shell probe");
        }
        if (opened.command != AdbWireMessage.OKAY || opened.arg1 != LOCAL_ID || opened.arg0 == 0) {
            throw new IOException("ADB shell channel did not return a valid OKAY");
        }
        final int remoteId = opened.arg0;
        byte[] outputBuffer = new byte[8192];
        int used = 0;
        try {
            while (true) {
                ensureOpen();
                AdbWireMessage message = read();
                if (message.arg0 != remoteId || message.arg1 != LOCAL_ID) {
                    throw new IOException("ADB shell packet channel identifiers do not match");
                }
                if (message.command == AdbWireMessage.WRTE) {
                    if (message.data.length > outputBuffer.length - used) {
                        throw new IOException("ADB shell probe output exceeded the 8 KiB limit");
                    }
                    System.arraycopy(message.data, 0, outputBuffer, used, message.data.length);
                    used += message.data.length;
                    write(new AdbWireMessage(AdbWireMessage.OKAY, LOCAL_ID, remoteId, null));
                    continue;
                }
                if (message.command == AdbWireMessage.CLSE) {
                    write(new AdbWireMessage(AdbWireMessage.CLSE, LOCAL_ID, remoteId, null));
                    String result = new String(outputBuffer, 0, used, StandardCharsets.UTF_8);
                    if (!result.contains(PROBE_MARKER)) {
                        throw new IOException("ADB shell channel closed without the expected probe marker");
                    }
                    return result.trim();
                }
                throw new IOException("ADB shell returned an unexpected packet command");
            }
        } finally {
            Arrays.fill(outputBuffer, (byte) 0);
        }
    }

    private AdbWireMessage read() throws IOException {
        ensureOpen();
        DataInputStream stream = input;
        if (stream == null) throw new IOException("ADB transport input is unavailable");
        AdbWireMessage message = AdbWireMessage.readFrom(stream);
        if (message.data.length > MAX_DATA_BYTES) {
            throw new IOException("ADB transport packet exceeds the configured limit");
        }
        return message;
    }

    private void write(AdbWireMessage message) throws IOException {
        ensureOpen();
        DataOutputStream stream = output;
        if (stream == null) throw new IOException("ADB transport output is unavailable");
        message.writeTo(stream);
    }

    private void ensureOpen() throws IOException {
        if (closed) throw new IOException("ADB shell probe was cancelled or closed");
    }

    @Override
    public void close() {
        // Do not return early when already closed: a socket may have been
        // published after a racing first close, and needs a second sweep.
        closed = true;
        closeResources();
    }

    private void closeResources() {
        SSLSocket secure = tlsSocket;
        tlsSocket = null;
        if (secure != null) {
            try { secure.close(); } catch (IOException ignored) { }
        }
        Socket socket = rawSocket;
        rawSocket = null;
        if (socket != null) {
            try { socket.close(); } catch (IOException ignored) { }
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
    }
}
