package roro.stellar.manager.adb;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

/** AOSP ADB pairing PeerInfo: an 8192-byte NUL-terminated typed UTF-8 record. */
final class PeerInfo {
    static final int RECORD_LENGTH = 8192;
    static final int DATA_LENGTH = RECORD_LENGTH - 1;

    enum Type {
        ADB_RSA_PUB_KEY((byte) 0),
        ADB_DEVICE_GUID((byte) 1);

        private final byte value;

        Type(byte value) { this.value = value; }

        byte getValue() { return value; }

        static Type fromValue(byte value) {
            for (Type type : values()) {
                if (type.value == value) return type;
            }
            return null;
        }
    }

    private final byte type;
    private final byte[] data;

    PeerInfo(byte type, byte[] source) {
        if (Type.fromValue(type) == null) {
            throw new IllegalArgumentException("Unknown ADB PeerInfo type: " + (type & 0xff));
        }
        if (source == null) throw new IllegalArgumentException("PeerInfo data is null");
        if (source.length > DATA_LENGTH - 1) {
            throw new IllegalArgumentException("PeerInfo UTF-8 text leaves no room for its NUL terminator");
        }
        for (byte value : source) {
            if (value == 0) throw new IllegalArgumentException("PeerInfo text contains an embedded NUL");
        }
        this.type = type;
        this.data = new byte[DATA_LENGTH];
        System.arraycopy(source, 0, data, 0, source.length);
        // The zero-initialised tail supplies the mandatory C-string terminator and padding.
    }

    byte getType() { return type; }

    byte[] getData() {
        return data.clone();
    }

    String getTextPayload() {
        int end = -1;
        for (int i = 0; i < data.length; i++) {
            if (data[i] == 0) {
                end = i;
                break;
            }
        }
        if (end < 0) {
            throw new IllegalArgumentException("PeerInfo payload is not NUL terminated");
        }
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(data, 0, end))
                    .toString();
        } catch (CharacterCodingException invalid) {
            throw new IllegalArgumentException("PeerInfo payload is not valid UTF-8", invalid);
        }
    }

    void writeTo(ByteBuffer output) {
        if (output == null || output.remaining() < RECORD_LENGTH) {
            throw new IllegalArgumentException("ADB peer-info buffer is too small");
        }
        output.put(type);
        output.put(data);
    }

    static PeerInfo readFrom(ByteBuffer input) {
        if (input == null || input.remaining() != RECORD_LENGTH) {
            throw new IllegalArgumentException("ADB peer-info record must be exactly 8192 bytes");
        }
        byte type = input.get();
        if (Type.fromValue(type) == null) {
            throw new IllegalArgumentException("Unknown ADB PeerInfo type: " + (type & 0xff));
        }
        byte[] data = new byte[DATA_LENGTH];
        input.get(data);
        PeerInfo decoded = new PeerInfo(type, new byte[0]);
        System.arraycopy(data, 0, decoded.data, 0, data.length);
        return decoded;
    }
}
