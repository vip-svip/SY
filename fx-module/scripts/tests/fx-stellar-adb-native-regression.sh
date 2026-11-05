#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LIB_ROOT="$ROOT/adhook/app/src/main/jniLibs"
JAVA="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/PairingContext.java"
WORKFLOW="$ROOT/.github/workflows/build-fx-adhook.yml"
fail(){ echo "FAIL: $*" >&2; exit 1; }

[ -s "$JAVA" ] || fail "original Stellar PairingContext JNI wrapper source missing"
[ -s "$WORKFLOW" ] || fail "FX APK source workflow missing"
[ -s "$LIB_ROOT/arm64-v8a/libadb.so" ] || fail "arm64-v8a libadb.so was not staged from original source"
[ -s "$LIB_ROOT/armeabi-v7a/libadb.so" ] || fail "armeabi-v7a libadb.so was not staged from original source"

for abi in arm64-v8a armeabi-v7a; do
    library="$LIB_ROOT/$abi/libadb.so"
    readelf -h "$library" >/dev/null 2>&1 || fail "$abi libadb.so is not a readable ELF"
    readelf -Ws "$library" | grep -Eq '[[:space:]]JNI_OnLoad$' || fail "$abi libadb.so does not export JNI_OnLoad"
    dynamic="$(readelf -d "$library")"
    printf '%s\n' "$dynamic" | grep -Fq 'libc.so' || fail "$abi libadb.so has no libc dependency"
    printf '%s\n' "$dynamic" | grep -Fq 'liblog.so' || fail "$abi libadb.so has no Android log dependency"
    printf '%s\n' "$dynamic" | grep -Fq 'libm.so' || fail "$abi libadb.so has no math dependency"
    printf '%s\n' "$dynamic" | grep -Fq 'libdl.so' || fail "$abi libadb.so has no dynamic-loader dependency"
done
readelf -h "$LIB_ROOT/arm64-v8a/libadb.so" | grep -Eq 'Class:[[:space:]]+ELF64' || fail "arm64-v8a libadb.so must be ELF64"
readelf -h "$LIB_ROOT/arm64-v8a/libadb.so" | grep -Eq 'Machine:[[:space:]]+AArch64' || fail "arm64-v8a libadb.so must target AArch64"
readelf -h "$LIB_ROOT/armeabi-v7a/libadb.so" | grep -Eq 'Class:[[:space:]]+ELF32' || fail "armeabi-v7a libadb.so must be ELF32"
readelf -h "$LIB_ROOT/armeabi-v7a/libadb.so" | grep -Eq 'Machine:[[:space:]]+ARM' || fail "armeabi-v7a libadb.so must target ARM"

# JNI_OnLoad registers this exact class path and these exact native descriptors.
grep -Fq 'package roro.stellar.manager.adb;' "$JAVA" || fail "JNI PairingContext package name changed"
grep -Fq 'public final class PairingContext' "$JAVA" || fail "JNI PairingContext class name changed"
grep -Fq 'System.loadLibrary("adb")' "$JAVA" || fail "PairingContext does not load the original libadb library"
grep -Fq 'private static native long nativeConstructor(boolean isClient, byte[] password);' "$JAVA" || fail "SPAKE2 constructor JNI descriptor changed"
grep -Fq 'private native byte[] nativeDecrypt(long pointer, byte[] payload);' "$JAVA" || fail "SPAKE2 decrypt JNI descriptor changed"
grep -Fq 'private native void nativeDestroy(long pointer);' "$JAVA" || fail "SPAKE2 destroy JNI descriptor changed"
grep -Fq 'private native byte[] nativeEncrypt(long pointer, byte[] payload);' "$JAVA" || fail "SPAKE2 encrypt JNI descriptor changed"
grep -Fq 'private native boolean nativeInitCipher(long pointer, byte[] peerMessage);' "$JAVA" || fail "SPAKE2 cipher-init JNI descriptor changed"
grep -Fq 'private native byte[] nativeMsg(long pointer);' "$JAVA" || fail "SPAKE2 message JNI descriptor changed"
grep -Fq 'Arrays.fill(secret, (byte) 0);' "$JAVA" || fail "pairing secret copy is not wiped after native context creation"
grep -Fq 'long pointer = nativePtr;' "$JAVA" || fail "native context destroy must snapshot the live pointer"
grep -Fq 'if (pointer == 0L) return;' "$JAVA" || fail "native context destroy is not idempotent"
grep -Fq 'nativePtr = 0L;' "$JAVA" || fail "native pointer is not invalidated before destroy"

# Compile the pure-Java JNI boundary and inspect JVM descriptors, without loading
# an Android .so into the Linux host VM.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fx-stellar-adb-jni.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
javac -d "$TMP/classes" "$JAVA" || fail "PairingContext Java JNI wrapper does not compile"
javap -classpath "$TMP/classes" -private -s roro.stellar.manager.adb.PairingContext > "$TMP/javap.txt"
for descriptor in '(Z[B)J' '(J[B)[B' '(J)V' '(J[B)Z' '(J)[B'; do
    grep -Fq "$descriptor" "$TMP/javap.txt" || fail "compiled Java native descriptors do not include $descriptor"
done

# Ensure the source workflow stages libraries from the original Stellar intake,
# not a checked-in binary copied from an unrelated release.
grep -Fq -- "-name '*_9.9.60_src'" "$WORKFLOW" || fail "workflow does not locate the original 9.9.60 source root"
grep -Fq 'for abi in arm64-v8a armeabi-v7a; do' "$WORKFLOW" || fail "workflow does not stage both supported Android ABIs"
grep -Fq 'native_source="$stellar_root/lib/$abi/libadb.so"' "$WORKFLOW" || fail "workflow does not read libadb.so from the original source tree"
grep -Fq 'native_target="adhook/app/src/main/jniLibs/$abi/libadb.so"' "$WORKFLOW" || fail "workflow does not stage the source library into Android jniLibs"

# Pairing header/peer-info codecs are byte-for-byte compatible with the original
# 9.9.60 Kotlin implementation, including its inclusive 0x4000 payload bound.
HEADER="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/PairingPacketHeader.java"
PEER="$ROOT/adhook/app/src/main/java/roro/stellar/manager/adb/PeerInfo.java"
[ -s "$HEADER" ] && [ -s "$PEER" ] || fail "ADB pairing frame/peer-info codec sources missing"
javac -d "$TMP/classes" "$HEADER" "$PEER" || fail "ADB pairing codec Java sources do not compile"
cat > "$TMP/PairingCodecSmoke.java" <<'JAVA'
package roro.stellar.manager.adb;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
public final class PairingCodecSmoke {
    private static void require(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        ByteBuffer valid = ByteBuffer.allocate(6).order(ByteOrder.BIG_ENDIAN);
        valid.put((byte) 1).put((byte) 1).putInt(0x4000).flip();
        PairingPacketHeader maximum = PairingPacketHeader.readFrom(valid);
        require(maximum != null && maximum.getPayload() == 0x4000,
                "original inclusive 0x4000 payload limit was rejected");
        require(maximum.getType() == PairingPacketHeader.Type.PEER_INFO.getValue(),
                "peer-info packet type changed");
        ByteBuffer encoded = ByteBuffer.allocate(6);
        maximum.writeTo(encoded);
        require(Arrays.equals(valid.array(), encoded.array()),
                "header encode/decode round trip changed the wire bytes");
        for (byte version : new byte[]{0, 2}) {
            ByteBuffer bad = ByteBuffer.allocate(6).put(version).put((byte) 0).putInt(1);
            bad.flip();
            require(PairingPacketHeader.readFrom(bad) == null,
                    "unsupported pairing protocol version was accepted");
        }
        ByteBuffer badType = ByteBuffer.allocate(6).put((byte) 1).put((byte) 2).putInt(1);
        badType.flip();
        require(PairingPacketHeader.readFrom(badType) == null,
                "unknown pairing frame type was accepted");
        for (int length : new int[]{0, 0x4001, -1}) {
            ByteBuffer bad = ByteBuffer.allocate(6).put((byte) 1).put((byte) 0).putInt(length);
            bad.flip();
            require(PairingPacketHeader.readFrom(bad) == null,
                    "invalid pairing payload length was accepted: " + length);
        }
        byte[] rsa = new byte[]{1, 2, 3, 4, 5};
        PeerInfo peer = new PeerInfo(PeerInfo.Type.ADB_RSA_PUB_KEY.getValue(), rsa);
        ByteBuffer peerWire = ByteBuffer.allocate(PeerInfo.RECORD_LENGTH);
        peer.writeTo(peerWire);
        require(peerWire.position() == 8192, "peer info must occupy exactly 8192 bytes");
        peerWire.flip();
        PeerInfo decoded = PeerInfo.readFrom(peerWire);
        require(decoded.getType() == 0, "original RSA peer-info type value changed");
        require(Arrays.equals(rsa, Arrays.copyOf(decoded.getData(), rsa.length)),
                "peer-info payload prefix did not survive round trip");
        require(decoded.getData().length == 8191, "peer-info data width changed");
        boolean shortRejected = false;
        try { PeerInfo.readFrom(ByteBuffer.allocate(PeerInfo.RECORD_LENGTH - 1)); }
        catch (IllegalArgumentException expected) { shortRejected = true; }
        require(shortRejected, "truncated peer-info payload was accepted");
        byte[] copy = decoded.getData();
        copy[0] = 99;
        require(decoded.getData()[0] == 1, "peer-info getter leaked its mutable backing array");
        System.out.println("PASS: original ADB pairing frame boundaries and fixed-width 8192-byte peer-info codec");
    }
}
JAVA
javac -cp "$TMP/classes" -d "$TMP/classes" "$TMP/PairingCodecSmoke.java" || fail "ADB pairing codec smoke test does not compile"
java -cp "$TMP/classes" roro.stellar.manager.adb.PairingCodecSmoke || fail "ADB pairing codec wire regression failed"

echo "PASS: original Stellar libadb ABIs, JNI_OnLoad, PairingContext JVM descriptors and source-staging provenance"
