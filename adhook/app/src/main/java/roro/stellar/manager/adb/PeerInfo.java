package roro.stellar.manager.adb;

import java.nio.ByteBuffer;

/** Fixed-size ADB pairing peer-info record (one type byte plus 8191 data bytes). */
final class PeerInfo {
    static final int DATA_LENGTH = 0x1fff;
    static final int RECORD_LENGTH = DATA_LENGTH + 1;

    enum Type {
        ADB_RSA_PUB_KEY((byte) 0),
        ADB_DEVICE_GUID((byte) 0);

        private final byte value;
        Type(byte value) { this.value = value; }
        byte getValue() { return value; }
    }

    private final byte type;
    private final byte[] data;

    PeerInfo(byte type, byte[] source) {
        if (source == null) throw new IllegalArgumentException("PeerInfo data is null");
        this.type = type;
        this.data = new byte[DATA_LENGTH];
        System.arraycopy(source, 0, data, 0, Math.min(source.length, DATA_LENGTH));
    }

    byte getType() { return type; }

    byte[] getData() {
        return data.clone();
    }

    void writeTo(ByteBuffer output) {
        if (output == null || output.remaining() < RECORD_LENGTH) {
            throw new IllegalArgumentException("ADB peer-info buffer is too small");
        }
        output.put(type);
        output.put(data);
    }

    static PeerInfo readFrom(ByteBuffer input) {
        if (input == null || input.remaining() < RECORD_LENGTH) {
            throw new IllegalArgumentException("ADB peer-info payload is truncated");
        }
        byte type = input.get();
        byte[] data = new byte[DATA_LENGTH];
        input.get(data);
        return new PeerInfo(type, data);
    }
}
