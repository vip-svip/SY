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
        PairingPacketHeader maximum = PairingPacketHeader.readFrom(
                ByteBuffer.wrap(new byte[]{1, 0, 0, 0, 0x40, 0}));
        check(maximum != null && maximum.getPayload() == 0x4000,
                "original inclusive 0x4000 maximum payload must be accepted");
        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{1, 0, 0, 0, 0x40, 1})) == null,
                "payload above the inclusive 0x4000 maximum must be rejected");
        check(PairingPacketHeader.readFrom(ByteBuffer.wrap(new byte[]{1, 0, 0, 0, 0})) == null,
                "truncated frame header must be rejected");

        check(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue() == 0,
                "AOSP host RSA key PeerInfo type must be zero");
        check(PeerInfo.Type.ADB_DEVICE_GUID.getValue() == 1,
                "AOSP device GUID PeerInfo type must be one");

        byte[] keyText = "AAAA user@host".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        PeerInfo hostKey = new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), keyText);
        ByteBuffer hostWire = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH);
        hostKey.writeTo(hostWire);
        check(hostWire.position() == 8192, "PeerInfo record must be exactly 8192 bytes");
        byte[] serialized = hostWire.array();
        check(serialized[0] == 0 && serialized[1] == 'A',
                "host RSA PeerInfo type or text prefix changed");
        check(serialized[PeerInfo.RECORD_LENGTH - 1] == 0,
                "PeerInfo must zero-pad its fixed-width UTF-8 text");
        hostWire.flip();
        PeerInfo decodedHost = PeerInfo.readFrom(hostWire);
        check(decodedHost.getType() == PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(),
                "host RSA PeerInfo type round-trip failed");
        check(decodedHost.getTextPayload().equals("AAAA user@host"),
                "host RSA PeerInfo NUL-terminated UTF-8 text round-trip failed");

        byte[] guidText = "adb-device-guid-012345".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        PeerInfo deviceGuid = new PeerInfo(PeerInfo.Type.ADB_DEVICE_GUID.getValue(), guidText);
        ByteBuffer guidWire = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH);
        deviceGuid.writeTo(guidWire);
        guidWire.flip();
        PeerInfo decodedGuid = PeerInfo.readFrom(guidWire);
        check(decodedGuid.getType() == 1, "device GUID PeerInfo type must round-trip as one");
        check(decodedGuid.getTextPayload().equals("adb-device-guid-012345"),
                "device GUID PeerInfo payload must decode to the mDNS identity");

        byte[] copied = decodedGuid.getData();
        copied[0] = 99;
        check(decodedGuid.getData()[0] == 'a', "PeerInfo getter exposed its mutable backing buffer");

        boolean unknownConstructorRejected = false;
        try { new PeerInfo((byte) 2, keyText); }
        catch (IllegalArgumentException expectedFailure) { unknownConstructorRejected = true; }
        check(unknownConstructorRejected, "unknown outgoing PeerInfo type was accepted");

        ByteBuffer unknownWire = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH);
        unknownWire.put((byte) 2);
        unknownWire.position(PeerInfo.RECORD_LENGTH);
        unknownWire.flip();
        boolean unknownIncomingRejected = false;
        try { PeerInfo.readFrom(unknownWire); }
        catch (IllegalArgumentException expectedFailure) { unknownIncomingRejected = true; }
        check(unknownIncomingRejected, "unknown incoming PeerInfo type was accepted");

        ByteBuffer overlongRecord = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH + 1);
        overlongRecord.position(overlongRecord.capacity()).flip();
        boolean overlongRejected = false;
        try { PeerInfo.readFrom(overlongRecord); }
        catch (IllegalArgumentException expectedFailure) { overlongRejected = true; }
        check(overlongRejected, "PeerInfo accepted trailing data beyond the exact 8192-byte record");

        ByteBuffer unterminatedWire = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH);
        unterminatedWire.put((byte) 1);
        while (unterminatedWire.hasRemaining()) unterminatedWire.put((byte) 'x');
        unterminatedWire.flip();
        boolean unterminatedRejected = false;
        try { PeerInfo.readFrom(unterminatedWire).getTextPayload(); }
        catch (IllegalArgumentException expectedFailure) { unterminatedRejected = true; }
        check(unterminatedRejected, "PeerInfo accepted a missing NUL terminator");

        byte[] tooLong = new byte[PeerInfo.DATA_LENGTH];
        boolean tooLongRejected = false;
        try { new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), tooLong); }
        catch (IllegalArgumentException expectedFailure) { tooLongRejected = true; }
        check(tooLongRejected, "PeerInfo payload that leaves no NUL terminator was accepted");

        boolean shortRejected = false;
        try { PeerInfo.readFrom(ByteBuffer.allocate(PeerInfo.RECORD_LENGTH - 1)); }
        catch (IllegalArgumentException expectedFailure) { shortRejected = true; }
        check(shortRejected, "truncated peer-info payload was accepted");
        System.out.println("PASS: ADB pairing frame header and fixed-width peer-info round-trip/bounds");
    }
}
JAVA

javac -d "$TMP/classes" "$HEADER" "$PEER" "$TMP/src/roro/stellar/manager/adb/AdbPacketCodecSmoke.java" \
    || fail "ADB pairing packet codec sources do not compile"
java -cp "$TMP/classes" roro.stellar.manager.adb.AdbPacketCodecSmoke \
    || fail "ADB pairing packet codec round-trip/bounds smoke test failed"
grep -Fq 'payload > MAX_PAYLOAD' "$HEADER" || fail "frame length bound must include 0x4000 and reject larger packets"
grep -Fq 'RECORD_LENGTH = DATA_LENGTH + 1' "$PEER" || fail "peer-info wire record width changed"
echo "PASS: original ADB pairing header/PeerInfo packet contract"
