#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
LIB_ROOT="$ROOT/adhook/app/src/main/jniLibs"
GRADLE="$ROOT/adhook/app/build.gradle"
WORKFLOW="$ROOT/.github/workflows/build-fx-adhook.yml"
fail(){ echo "FAIL: $*" >&2; exit 1; }

[ -s "$GRADLE" ] || fail "FX app Gradle configuration is missing"
[ -s "$WORKFLOW" ] || fail "source intake workflow is missing"
grep -Fq "useLegacyPackaging true" "$GRADLE" || fail "native executable libraries are not extracted into nativeLibraryDir"
grep -Fq "abiFilters 'arm64-v8a', 'armeabi-v7a'" "$GRADLE" || fail "APK ABI filters do not match the original Stellar native payloads"
grep -Fq 'native_source="$stellar_root/lib/$abi/$executable"' "$WORKFLOW" || fail "workflow does not stage launcher files from the original 9.9.60 tree"
grep -Fq 'for executable in libstellar.so libchid.so; do' "$WORKFLOW" || fail "workflow does not stage the original daemon and privilege-drop helper"
grep -Fq 'install -D -m 0755 "$native_source" "$native_target"' "$WORKFLOW" || fail "native launcher files are not staged with executable permissions"

for abi in arm64-v8a armeabi-v7a; do
    case "$abi" in
      arm64-v8a) class=ELF64; machine=AArch64 ;;
      armeabi-v7a) class=ELF32; machine=ARM ;;
    esac
    for name in libstellar.so libchid.so; do
        file="$LIB_ROOT/$abi/$name"
        [ -s "$file" ] || fail "$abi/$name was not staged from original source"
        [ -x "$file" ] || fail "$abi/$name is not executable in the staged app source set"
        readelf -h "$file" >/dev/null 2>&1 || fail "$abi/$name is not a readable ELF"
        readelf -h "$file" | grep -Fq "$class" || fail "$abi/$name has the wrong ELF class"
        readelf -h "$file" | grep -Fq "$machine" || fail "$abi/$name has the wrong CPU architecture"
        entry=$(readelf -h "$file" | awk '/Entry point address:/ {print $4}')
        [ -n "$entry" ] || fail "$abi/$name has no ELF entry point field"
        case "$entry" in 0x0|0x00000000|0x0000000000000000) fail "$abi/$name has a zero entry point and cannot be used as the original command launcher";; esac
    done
done

echo "PASS: original Stellar libstellar/libchid executable payloads are staged for both ABIs and extracted into nativeLibraryDir"
