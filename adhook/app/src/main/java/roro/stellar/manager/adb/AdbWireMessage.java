package roro.stellar.manager.adb;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.zip.CRC32;

/** Bounds-checked ADB transport packet codec matching the original Stellar wire format. */
final class AdbWireMessage {
    static final int HEADER_BYTES = 24;
    static final int MAX_DATA_BYTES = 1024 * 1024;

    static final int CNXN = fourCC("CNXN");
    static final int AUTH = fourCC("AUTH");
    static final int STLS = fourCC("STLS");
    static final int OPEN = fourCC("OPEN");
    static final int OKAY = fourCC("OKAY");
    static final int WRTE = fourCC("WRTE");
    static final int CLSE = fourCC("CLSE");

    final int command;
    final int arg0;
    final int arg1;
    final byte[] data;

    AdbWireMessage(int command, int arg0, int arg1, byte[] data) {
        if (data != null && data.length > MAX_DATA_BYTES) {
            throw new IllegalArgumentException("ADB packet exceeds the configured data limit");
        }
        this.command = command;
        this.arg0 = arg0;
        this.arg1 = arg1;
        this.data = data == null ? new byte[0] : data.clone();
    }

    static int fourCC(String value) {
        if (value == null || value.length() != 4) {
            throw new IllegalArgumentException("ADB command must be four ASCII characters");
        }
        for (int i = 0; i < 4; i++) {
            if (value.charAt(i) < 0x20 || value.charAt(i) > 0x7e) {
                throw new IllegalArgumentException("ADB command contains non-ASCII characters");
            }
        }
        return value.charAt(0)
                | (value.charAt(1) << 8)
                | (value.charAt(2) << 16)
                | (value.charAt(3) << 24);
    }

    byte[] encode() {
        CRC32 crc = new CRC32();
        crc.update(data);
        ByteBuffer output = ByteBuffer.allocate(HEADER_BYTES + data.length)
                .order(ByteOrder.LITTLE_ENDIAN);
        output.putInt(command)
                .putInt(arg0)
                .putInt(arg1)
                .putInt(data.length)
                .putInt((int) crc.getValue())
                .putInt(~command)
                .put(data);
        return output.array();
    }

    void writeTo(DataOutputStream output) throws IOException {
        output.write(encode());
        output.flush();
    }

    static AdbWireMessage readFrom(DataInputStream input) throws IOException {
        byte[] header = new byte[HEADER_BYTES];
        input.readFully(header);
        ByteBuffer packet = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
        int command = packet.getInt();
        int arg0 = packet.getInt();
        int arg1 = packet.getInt();
        int length = packet.getInt();
        int checksum = packet.getInt();
        int magic = packet.getInt();
        if (magic != ~command) {
            throw new IOException("ADB packet magic does not match its command");
        }
        if (length < 0 || length > MAX_DATA_BYTES) {
            throw new IOException("ADB packet length is outside the configured limit");
        }
        byte[] payload = new byte[length];
        if (length > 0) {
            input.readFully(payload);
            CRC32 crc = new CRC32();
            crc.update(payload);
            if ((int) crc.getValue() != checksum) {
                throw new IOException("ADB packet payload checksum mismatch");
            }
        } else if (checksum != 0) {
            throw new IOException("ADB empty packet has a non-zero checksum");
        }
        return new AdbWireMessage(command, arg0, arg1, payload);
    }

    static byte[] nulTerminatedUtf8(String value) {
        if (value == null || value.indexOf('\0') >= 0) {
            throw new IllegalArgumentException("ADB service string is invalid");
        }
        byte[] raw = value.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        byte[] result = java.util.Arrays.copyOf(raw, raw.length + 1);
        java.util.Arrays.fill(raw, (byte) 0);
        return result;
    }
}
