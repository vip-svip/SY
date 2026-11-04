#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SRC="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb"
HEADER="$SRC/PairingPacketHeader.java"
PEER="$SRC/PeerInfo.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -s "$HEADER" ] && [ -s "$PEER" ] || fail "original ADB pairing packet codecs are missing"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-adb-packet.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/src/roro/stellar/manager/adb" "$TMP/classes"
cat > "$TMP/src/roro/stellar/manager/adb/AdbPacketCodecSmoke.java" <<'JAVA'
package roro.stellar.manager.adb;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

public final class AdbPacketCodecSmoke {
    private static void check(boolean ok, String reason) {
        if (!ok) throw new AssertionError(reason);
    }

    public static void main(String[] args) {
        ByteBuffer headerBytes = ByteBuffer.allocate(PairingPacketHeader.SIZE_BYTES)
                .order(ByteOrder.BIG_ENDIAN);
        new PairingPacketHeader((byte) 1,
                PairingPacketHeader.Type.SPAKE2_MSG.getValue(), 3).writeTo(headerBytes);
        byte[] expected = new byte[]{1, 0, 0, 0, 0, 3};
        check(Arrays.equals(expected, headerBytes.array()),
                "ADB header must be version/type/big-endian-length");
        headerBytes.flip();
        PairingPacketHeader header = PairingPacketHeader.readFrom(headerBytes);
        check(header != null && header.getVersion() == 1
                        && header.getType() == PairingPacketHeader.Type.SPAKE2_MSG.getValue()
                        && header.getPayload() == 3,
                "valid SPAKE2 header did not round-trip");

        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{0, 0, 0, 0, 0, 1})) == null,
                "version zero must be rejected");
        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{1, 2, 0, 0, 0, 1})) == null,
                "unknown frame type must be rejected");
        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{1, 0, 0, 0, 0, 0})) == null,
                "zero payload must be rejected");
        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{1, 0, 0, 0, 0, 0x40})) == null,
                "payload at the exclusive 0x4000 upper bound must be rejected");
        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{1, 0, 0, 0, 0})) == null,
                "truncated frame header must be rejected");

        byte[] input = new byte[]{10, 20, 30};
        PeerInfo peer = new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), input);
        ByteBuffer peerBytes = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH);
        peer.writeTo(peerBytes);
        check(peerBytes.position() == PeerInfo.RECORD_LENGTH,
                "PeerInfo record must be exactly 8192 bytes");
        byte[] serialized = peerBytes.array();
        check(serialized[0] == 0 && serialized[1] == 10
                        && serialized[2] == 20 && serialized[3] == 30,
                "PeerInfo type or source bytes changed");
        check(serialized[PeerInfo.RECORD_LENGTH - 1] == 0,
                "PeerInfo must zero-pad its fixed-width payload");
        peerBytes.flip();
        PeerInfo decoded = PeerInfo.readFrom(peerBytes);
        check(decoded.getType() == peer.getType(), "PeerInfo type round-trip failed");
        check(Arrays.equals(peer.getData(), decoded.getData()), "PeerInfo data round-trip failed");

        byte[] oversized = new byte[PeerInfo.DATA_LENGTH + 17];
        Arrays.fill(oversized, (byte) 0x5a);
        PeerInfo truncated = new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), oversized);
        check(truncated.getData().length == PeerInfo.DATA_LENGTH,
                "PeerInfo oversized data was not truncated to the original field width");
        check(truncated.getData()[PeerInfo.DATA_LENGTH - 1] == (byte) 0x5a,
                "PeerInfo truncation lost the final permitted byte");
        try {
            PeerInfo.readFrom(ByteBuffer.allocate(PeerInfo.RECORD_LENGTH - 1));
            throw new AssertionError("truncated peer-info payload was accepted");
        } catch (IllegalArgumentException expectedFailure) {
            // Fail closed before consuming an incomplete fixed-size record.
        }
        System.out.println("PASS: ADB pairing frame header and fixed-width peer-info round-trip/bounds");
    }
}
JAVA

javac -d "$TMP/classes" "$HEADER" "$PEER" "$TMP/src/roro/stellar/manager/adb/AdbPacketCodecSmoke.java" \
    || fail "ADB pairing packet codec sources do not compile"
java -cp "$TMP/classes" roro.stellar.manager.adb.AdbPacketCodecSmoke \
    || fail "ADB pairing packet codec round-trip/bounds smoke test failed"
grep -Fq 'payload >= MAX_PAYLOAD' "$HEADER" || fail "frame length bound is not exclusive at 0x4000"
grep -Fq 'RECORD_LENGTH = DATA_LENGTH + 1' "$PEER" || fail "peer-info wire record width changed"
echo "PASS: original ADB pairing header/PeerInfo packet contract"
