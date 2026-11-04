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
echo "PASS: original Stellar libadb ABIs, JNI_OnLoad, PairingContext JVM descriptors and source-staging provenance"
