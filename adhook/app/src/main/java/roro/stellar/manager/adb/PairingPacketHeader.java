package roro.stellar.manager.adb;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** ADB wireless pairing frame header: version(1), type(1), payload length(4). */
final class PairingPacketHeader {
    static final int SIZE_BYTES = 6;
    static final int MIN_PAYLOAD = 1;
    static final int MAX_PAYLOAD = 0x4000;

    enum Type {
        SPAKE2_MSG((byte) 0),
        PEER_INFO((byte) 1);

        private final byte value;
        Type(byte value) { this.value = value; }
        byte getValue() { return value; }

        static Type fromValue(byte value) {
            for (Type type : values()) if (type.value == value) return type;
            return null;
        }
    }

    private final byte version;
    private final byte type;
    private final int payload;

    PairingPacketHeader(byte version, byte type, int payload) {
        this.version = version;
        this.type = type;
        this.payload = payload;
    }

    byte getVersion() { return version; }
    byte getType() { return type; }
    int getPayload() { return payload; }

    void writeTo(ByteBuffer output) {
        if (output == null || output.remaining() < SIZE_BYTES) {
            throw new IllegalArgumentException("ADB pairing header buffer is too small");
        }
        output.order(ByteOrder.BIG_ENDIAN)
                .put(version)
                .put(type)
                .putInt(payload);
    }

    static PairingPacketHeader readFrom(ByteBuffer input) {
        if (input == null || input.remaining() < SIZE_BYTES) return null;
        input.order(ByteOrder.BIG_ENDIAN);
        byte version = input.get();
        byte type = input.get();
        int payload = input.getInt();
        if (version != 1 || Type.fromValue(type) == null
                || payload < MIN_PAYLOAD || payload >= MAX_PAYLOAD) {
            return null;
        }
        return new PairingPacketHeader(version, type, payload);
    }
}
