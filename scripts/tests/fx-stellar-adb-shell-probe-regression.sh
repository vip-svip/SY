#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SRC="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb"
WIRE="$SRC/AdbWireMessage.java"
CLIENT="$SRC/AdbShellProbeClient.java"
ACTIVITY="$SRC/AdbPairingActivity.java"
WORKFLOW="$ROOT/.github/workflows/build-fx-adhook.yml"
fail(){ echo "FAIL: $*" >&2; exit 1; }
for file in "$WIRE" "$CLIENT" "$ACTIVITY" "$WORKFLOW"; do
    [ -s "$file" ] || fail "ADB shell probe migration source missing: $file"
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-adb-shell-probe.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/stub/roro/stellar/manager/adb" "$TMP/test/roro/stellar/manager/adb" "$TMP/classes"
cat > "$TMP/stub/roro/stellar/manager/adb/AdbKey.java" <<'JAVA'
package roro.stellar.manager.adb;
import java.security.GeneralSecurityException;
import javax.net.ssl.SSLContext;
/** Host-JDK compile stub for the AndroidKeyStore-backed production identity. */
public final class AdbKey {
    public SSLContext getSslContext() { return null; }
    public byte[] sign(byte[] token) throws GeneralSecurityException { return new byte[256]; }
    public byte[] getAdbPublicKey() { return new byte[]{'A','D','B',0}; }
}
JAVA
cat > "$TMP/test/roro/stellar/manager/adb/AdbWireSmoke.java" <<'JAVA'
package roro.stellar.manager.adb;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;

public final class AdbWireSmoke {
    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }
    private static void rejects(byte[] bytes, String message) throws Exception {
        boolean rejected = false;
        try {
            AdbWireMessage.readFrom(new DataInputStream(new ByteArrayInputStream(bytes)));
        } catch (IOException expected) {
            rejected = true;
        }
        check(rejected, message);
    }
    public static void main(String[] args) throws Exception {
        check(AdbWireMessage.CNXN == 0x4e584e43, "CNXN command byte order changed");
        check(AdbWireMessage.STLS == 0x534c5453, "STLS command byte order changed");
        check(AdbWireMessage.AUTH == 0x48545541, "AUTH command byte order changed");
        check(AdbWireMessage.OPEN == 0x4e45504f, "OPEN command byte order changed");
        check(AdbWireMessage.OKAY == 0x59414b4f, "OKAY command byte order changed");
        check(AdbWireMessage.WRTE == 0x45545257, "WRTE command byte order changed");
        check(AdbWireMessage.CLSE == 0x45534c43, "CLSE command byte order changed");

        byte[] service = AdbWireMessage.nulTerminatedUtf8("shell:echo FX_ADB_SHELL_CONNECTED");
        check(service[service.length - 1] == 0, "ADB OPEN destination must be NUL terminated");
        AdbWireMessage outgoing = new AdbWireMessage(AdbWireMessage.OPEN, 1, 0, service);
        byte[] encoded = outgoing.encode();
        ByteBuffer header = ByteBuffer.wrap(encoded).order(ByteOrder.LITTLE_ENDIAN);
        check(header.getInt() == AdbWireMessage.OPEN, "ADB command was not encoded little-endian");
        check(header.getInt() == 1 && header.getInt() == 0, "ADB local/remote channel IDs changed");
        check(header.getInt() == service.length, "ADB data length field changed");
        check(header.getInt() != 0, "non-empty ADB payload checksum must be populated");
        check(header.getInt() == ~AdbWireMessage.OPEN, "ADB command magic must be command XOR 0xffffffff");

        AdbWireMessage decoded = AdbWireMessage.readFrom(
                new DataInputStream(new ByteArrayInputStream(encoded)));
        check(decoded.command == AdbWireMessage.OPEN, "ADB packet command did not round-trip");
        check(decoded.arg0 == 1 && decoded.arg1 == 0, "ADB packet channel IDs did not round-trip");
        check(Arrays.equals(decoded.data, service), "ADB packet payload did not round-trip");

        byte[] badMagic = encoded.clone();
        badMagic[20] ^= 1;
        rejects(badMagic, "ADB packet with invalid command magic was accepted");
        byte[] badChecksum = encoded.clone();
        badChecksum[16] ^= 1;
        rejects(badChecksum, "ADB packet with invalid CRC32 was accepted");

        ByteBuffer oversizedHeader = ByteBuffer.allocate(AdbWireMessage.HEADER_BYTES)
                .order(ByteOrder.LITTLE_ENDIAN);
        oversizedHeader.putInt(AdbWireMessage.WRTE).putInt(7).putInt(1)
                .putInt(AdbWireMessage.MAX_DATA_BYTES + 1).putInt(0).putInt(~AdbWireMessage.WRTE);
        rejects(oversizedHeader.array(), "oversized ADB frame was accepted before allocation");

        ByteBuffer negativeHeader = ByteBuffer.allocate(AdbWireMessage.HEADER_BYTES)
                .order(ByteOrder.LITTLE_ENDIAN);
        negativeHeader.putInt(AdbWireMessage.WRTE).putInt(7).putInt(1)
                .putInt(-1).putInt(0).putInt(~AdbWireMessage.WRTE);
        rejects(negativeHeader.array(), "negative ADB data length was accepted");

        ByteArrayOutputStream empty = new ByteArrayOutputStream();
        new AdbWireMessage(AdbWireMessage.CLSE, 1, 4, null)
                .writeTo(new java.io.DataOutputStream(empty));
        AdbWireMessage emptyDecoded = AdbWireMessage.readFrom(
                new DataInputStream(new ByteArrayInputStream(empty.toByteArray())));
        check(emptyDecoded.command == AdbWireMessage.CLSE && emptyDecoded.data.length == 0,
                "empty ADB control packet did not round-trip");

        boolean nulRejected = false;
        try {
            AdbWireMessage.nulTerminatedUtf8("shell:echo" + ((char) 0) + "injected");
        } catch (IllegalArgumentException expected) {
            nulRejected = true;
        }
        check(nulRejected, "ADB service destination accepted an embedded NUL");
        System.out.println("PASS: ADB packet framing, LE fields, CRC32, command magic, bounded lengths and NUL-safe service encoding");
    }
}
JAVA

javac -d "$TMP/classes" \
    "$TMP/stub/roro/stellar/manager/adb/AdbKey.java" \
    "$WIRE" "$CLIENT" \
    "$TMP/test/roro/stellar/manager/adb/AdbWireSmoke.java" \
    || fail "ADB wire codec and production ADB shell probe do not compile on the host JDK"
java -cp "$TMP/classes" roro.stellar.manager.adb.AdbWireSmoke \
    || fail "ADB wire framing regression failed"

grep -Fq 'connectAndAuthenticate()' "$CLIENT" || fail "ADB probe does not complete CNXN/STLS/AUTH"
grep -Fq 'response.command != AdbWireMessage.STLS' "$CLIENT" || fail "ADB connect must fail closed unless TLS upgrade is requested"
grep -Fq 'secure.setEnabledProtocols(new String[]{"TLSv1.3"})' "$CLIENT" || fail "ADB shell connection is not pinned to TLS 1.3"
grep -Fq 'key.sign(challenge.data)' "$CLIENT" || fail "ADB AUTH challenge is not signed by the paired host key"
grep -Fq 'key.getAdbPublicKey()' "$CLIENT" || fail "ADB AUTH public-key fallback is missing"
grep -Fq 'shell:echo ' "$CLIENT" || fail "ADB probe is not restricted to its fixed echo service"
grep -Fq 'public synchronized String probe()' "$CLIENT" || fail "ADB probe has no one-shot fixed-command entry point"
! grep -Fq 'execute(String command' "$CLIENT" || fail "ADB probe must not expose arbitrary shell command execution"
grep -Fq 'MAX_DATA_BYTES = 1024 * 1024' "$WIRE" || fail "ADB packet decoder lacks a frame-size limit"
grep -Fq 'magic != ~command' "$WIRE" || fail "ADB command magic is not validated"
grep -Fq 'payload checksum mismatch' "$WIRE" || fail "ADB packet CRC32 is not validated"
grep -Fq 'probeSelectedConnectEndpoint()' "$ACTIVITY" || fail "ADB connect endpoint probe is not wired to the Activity"
grep -Fq 'new AdbShellProbeClient(target.host, target.port, key)' "$ACTIVITY" || fail "selected connect host/port are not passed to the ADB probe"
grep -Fq 'probeWorker.shutdownNow()' "$ACTIVITY" || fail "ADB probe worker is not lifecycle-bound"
grep -Fq 'probing.close()' "$ACTIVITY" || fail "lost endpoint or Activity teardown cannot abort a blocked ADB socket"
echo "PASS: TLS-only ADB AUTH and fixed read-only Shell probe are connected to the selected connect endpoint"
