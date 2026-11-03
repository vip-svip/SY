package de.privacyguard.adhook.imported.dia;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Bounded, read-only DEX index parser for Dia's class/method/field browser.
 * It never defines or executes classes from the inspected APK.
 */
public final class FxDiaDexIndex {
    private static final int MAX_DEX_BYTES = 96 * 1024 * 1024;
    private static final int MAX_CLASSES = 100000;
    private static final int MAX_MEMBERS_PER_CLASS = 20000;

    public static final class Member {
        public final boolean method;
        public final String name;
        public final String descriptor;
        public final int accessFlags;

        Member(boolean method, String name, String descriptor, int accessFlags) {
            this.method = method;
            this.name = name;
            this.descriptor = descriptor;
            this.accessFlags = accessFlags;
        }

        public String display() {
            return (method ? "方法 " : "字段 ") + name + descriptor
                    + "  [access=0x" + Integer.toHexString(accessFlags) + "]";
        }
    }

    public static final class DexClass {
        public final String descriptor;
        public final List<Member> fields = new ArrayList<>();
        public final List<Member> methods = new ArrayList<>();

        DexClass(String descriptor) { this.descriptor = descriptor; }
        public String javaName() {
            if (descriptor == null || descriptor.length() < 2) return descriptor;
            return descriptor.substring(1, descriptor.length() - 1).replace('/', '.');
        }
    }

    private final byte[] data;
    private final int stringsSize, stringsOff, typesSize, typesOff;
    private final int protosSize, protosOff, fieldsSize, fieldsOff;
    private final int methodsSize, methodsOff, classesSize, classesOff;
    private final String[] stringCache;
    private final String[] typeCache;

    private FxDiaDexIndex(byte[] data) throws IOException {
        this.data = data;
        if (data.length < 112 || data[0] != 'd' || data[1] != 'e'
                || data[2] != 'x' || data[3] != '\n')
            throw new IOException("not a DEX file");
        stringsSize = u32(0x38); stringsOff = u32(0x3c);
        typesSize = u32(0x40); typesOff = u32(0x44);
        protosSize = u32(0x48); protosOff = u32(0x4c);
        fieldsSize = u32(0x50); fieldsOff = u32(0x54);
        methodsSize = u32(0x58); methodsOff = u32(0x5c);
        classesSize = u32(0x60); classesOff = u32(0x64);
        checkArray(stringsOff, stringsSize, 4);
        checkArray(typesOff, typesSize, 4);
        checkArray(protosOff, protosSize, 12);
        checkArray(fieldsOff, fieldsSize, 8);
        checkArray(methodsOff, methodsSize, 8);
        checkArray(classesOff, classesSize, 32);
        stringCache = new String[stringsSize];
        typeCache = new String[typesSize];
    }

    public static Map<String, DexClass> readApks(List<String> apkPaths) throws IOException {
        LinkedHashMap<String, DexClass> all = new LinkedHashMap<>();
        if (apkPaths == null) return all;
        for (String path : apkPaths) {
            if (path == null || path.isEmpty()) continue;
            try (ZipFile zip = new ZipFile(path)) {
                List<? extends ZipEntry> dexEntries = new ArrayList<>();
                Enumeration<? extends ZipEntry> entries = zip.entries();
                List<ZipEntry> ordered = new ArrayList<>();
                while (entries.hasMoreElements()) {
                    ZipEntry entry = entries.nextElement();
                    if (entry.isDirectory()) continue;
                    String name = entry.getName();
                    if (name.matches("classes([2-9]|[1-9][0-9]*)?\\.dex")) ordered.add(entry);
                }
                ordered.sort(java.util.Comparator.comparingInt(entry -> dexOrder(entry.getName())));
                for (ZipEntry entry : ordered) {
                    byte[] bytes;
                    try (InputStream input = zip.getInputStream(entry)) {
                        bytes = readBounded(input, MAX_DEX_BYTES);
                    }
                    FxDiaDexIndex index = new FxDiaDexIndex(bytes);
                    index.appendClasses(all);
                    if (all.size() >= MAX_CLASSES) return all;
                }
            }
        }
        return all;
    }

    private static int dexOrder(String name) {
        if ("classes.dex".equals(name)) return 1;
        try { return Integer.parseInt(name.substring(7, name.length() - 4)); }
        catch (RuntimeException ignored) { return Integer.MAX_VALUE; }
    }

    private static byte[] readBounded(InputStream input, int max) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[16384];
        int n;
        while ((n = input.read(buffer)) != -1) {
            if (output.size() > max - n) throw new IOException("DEX entry exceeds " + max + " bytes");
            output.write(buffer, 0, n);
        }
        return output.toByteArray();
    }

    private void appendClasses(Map<String, DexClass> output) throws IOException {
        for (int i = 0; i < classesSize && output.size() < MAX_CLASSES; i++) {
            int base = classesOff + i * 32;
            int classIndex = u32(base);
            if (classIndex < 0 || classIndex >= typesSize) continue;
            String descriptor = type(classIndex);
            if (descriptor == null || !descriptor.startsWith("L")) continue;
            DexClass item = output.get(descriptor);
            if (item == null) {
                item = new DexClass(descriptor);
                output.put(descriptor, item);
            }
            int classDataOff = u32(base + 24);
            if (classDataOff == 0) continue;
            parseClassData(classDataOff, item);
        }
    }

    private void parseClassData(int offset, DexClass item) throws IOException {
        int[] cursor = {offset};
        int staticFields = readUleb(cursor);
        int instanceFields = readUleb(cursor);
        int directMethods = readUleb(cursor);
        int virtualMethods = readUleb(cursor);
        long fieldTotal = (long) staticFields + instanceFields;
        long methodTotal = (long) directMethods + virtualMethods;
        if (fieldTotal > MAX_MEMBERS_PER_CLASS || methodTotal > MAX_MEMBERS_PER_CLASS)
            throw new IOException("class member count exceeds safety limit");
        parseFieldList(cursor, staticFields, item);
        parseFieldList(cursor, instanceFields, item);
        parseMethodList(cursor, directMethods, item);
        parseMethodList(cursor, virtualMethods, item);
    }

    private void parseFieldList(int[] cursor, int count, DexClass item) throws IOException {
        int fieldIndex = 0;
        for (int i = 0; i < count; i++) {
            fieldIndex += readUleb(cursor);
            int access = readUleb(cursor);
            if (fieldIndex < 0 || fieldIndex >= fieldsSize) throw new IOException("bad field index");
            int p = fieldsOff + fieldIndex * 8;
            int typeIndex = u16(p + 2);
            int nameIndex = u32(p + 4);
            String name = string(nameIndex);
            String desc = type(typeIndex);
            if (name != null && desc != null) item.fields.add(
                    new Member(false, name, ":" + desc, access));
        }
    }

    private void parseMethodList(int[] cursor, int count, DexClass item) throws IOException {
        int methodIndex = 0;
        for (int i = 0; i < count; i++) {
            methodIndex += readUleb(cursor);
            int access = readUleb(cursor);
            readUleb(cursor); // code_off; inspect metadata only, never execute it
            if (methodIndex < 0 || methodIndex >= methodsSize) throw new IOException("bad method index");
            int p = methodsOff + methodIndex * 8;
            int protoIndex = u16(p + 2);
            int nameIndex = u32(p + 4);
            String name = string(nameIndex);
            String signature = proto(protoIndex);
            if (name != null && signature != null) item.methods.add(
                    new Member(true, name, signature, access));
        }
    }

    private String proto(int index) throws IOException {
        if (index < 0 || index >= protosSize) return null;
        int p = protosOff + index * 12;
        int returnType = u32(p + 4);
        int parametersOff = u32(p + 8);
        StringBuilder signature = new StringBuilder("(");
        if (parametersOff != 0) {
            int count = u32(parametersOff);
            if (count > 4096) throw new IOException("method parameter count exceeds limit");
            checkRange(parametersOff + 4, count * 2);
            for (int i = 0; i < count; i++) signature.append(type(u16(parametersOff + 4 + i * 2)));
        }
        return signature.append(')').append(type(returnType)).toString();
    }

    private String type(int index) throws IOException {
        if (index < 0 || index >= typesSize) return null;
        String cached = typeCache[index];
        if (cached != null) return cached;
        int stringIndex = u32(typesOff + index * 4);
        String descriptor = string(stringIndex);
        typeCache[index] = descriptor;
        return descriptor;
    }

    private String string(int index) throws IOException {
        if (index < 0 || index >= stringsSize) return null;
        String cached = stringCache[index];
        if (cached != null) return cached;
        int dataOff = u32(stringsOff + index * 4);
        int[] cursor = {dataOff};
        readUleb(cursor); // UTF-16 length; identifiers and descriptors are bounded below
        int start = cursor[0], end = start;
        while (end < data.length && data[end] != 0) end++;
        if (end >= data.length) throw new IOException("unterminated DEX string");
        String value = new String(data, start, end - start, java.nio.charset.StandardCharsets.UTF_8);
        stringCache[index] = value;
        return value;
    }

    private int readUleb(int[] cursor) throws IOException {
        int result = 0;
        int shift = 0;
        for (int i = 0; i < 5; i++) {
            if (cursor[0] >= data.length) throw new IOException("truncated ULEB128");
            int value = data[cursor[0]++] & 0xff;
            result |= (value & 0x7f) << shift;
            if ((value & 0x80) == 0) return result;
            shift += 7;
        }
        throw new IOException("invalid ULEB128");
    }

    private int u16(int offset) throws IOException {
        checkRange(offset, 2);
        return (data[offset] & 0xff) | ((data[offset + 1] & 0xff) << 8);
    }
    private int u32(int offset) throws IOException {
        checkRange(offset, 4);
        long value = (data[offset] & 0xffL)
                | ((data[offset + 1] & 0xffL) << 8)
                | ((data[offset + 2] & 0xffL) << 16)
                | ((data[offset + 3] & 0xffL) << 24);
        if (value > Integer.MAX_VALUE) throw new IOException("DEX offset exceeds addressable range");
        return (int) value;
    }
    private void checkArray(int offset, int count, int width) throws IOException {
        if (count < 0 || offset < 0) throw new IOException("negative DEX table size/offset");
        if (count == 0) return;
        long length = (long) count * width;
        if (length > Integer.MAX_VALUE) throw new IOException("DEX table too large");
        checkRange(offset, (int) length);
    }
    private void checkRange(int offset, int length) throws IOException {
        if (offset < 0 || length < 0 || (long) offset + length > data.length)
            throw new IOException("DEX offset out of range");
    }
}
