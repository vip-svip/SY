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
    private static final int MAX_CALLS_PER_CLASS = 512;
    private static final int MAX_CALLS_PER_DEX = 150000;
    private static final int MAX_CODE_UNITS_PER_METHOD = 2 * 1024 * 1024;

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

    public static final class CallSite {
        public final String caller;
        public final String callee;
        public final String opcode;

        CallSite(String caller, String callee, String opcode) {
            this.caller = caller;
            this.callee = callee;
            this.opcode = opcode;
        }

        public String display() { return caller + "  --" + opcode + "-->  " + callee; }
    }

    public static final class DexClass {
        public final String descriptor;
        public final List<Member> fields = new ArrayList<>();
        public final List<Member> methods = new ArrayList<>();
        public final List<CallSite> calls = new ArrayList<>();
        public String superDescriptor;
        public final List<String> interfaces = new ArrayList<>();

        DexClass(String descriptor) { this.descriptor = descriptor; }
        public String javaName() {
            if (descriptor == null || descriptor.length() < 2) return descriptor;
            return descriptor.substring(1, descriptor.length() - 1).replace('/', '.');
        }
    }

    private int parsedCallEdges;
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

    /** Parse one standalone DEX stream, such as Dia's bundled Android framework index. */
    public static Map<String, DexClass> readDex(InputStream input) throws IOException {
        byte[] bytes = readBounded(input, MAX_DEX_BYTES);
        FxDiaDexIndex index = new FxDiaDexIndex(bytes);
        LinkedHashMap<String, DexClass> classes = new LinkedHashMap<>();
        index.appendClasses(classes);
        return classes;
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
            long superIndex = u32Bits(base + 12);
            if (superIndex != 0xffffffffL && superIndex < typesSize) {
                item.superDescriptor = type((int) superIndex);
            }
            int interfacesOff = u32(base + 16);
            if (interfacesOff > 0) {
                int interfaceCount = u32(interfacesOff);
                if (interfaceCount > 4096) throw new IOException("class interface count exceeds limit");
                checkRange(interfacesOff + 4, interfaceCount * 2);
                for (int j = 0; j < interfaceCount; j++) {
                    String iface = type(u16(interfacesOff + 4 + j * 2));
                    if (iface != null && !item.interfaces.contains(iface)) item.interfaces.add(iface);
                }
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
            int codeOff = readUleb(cursor);
            if (methodIndex < 0 || methodIndex >= methodsSize) throw new IOException("bad method index");
            int p = methodsOff + methodIndex * 8;
            int protoIndex = u16(p + 2);
            int nameIndex = u32(p + 4);
            String name = string(nameIndex);
            String signature = proto(protoIndex);
            if (name == null || signature == null) continue;
            item.methods.add(new Member(true, name, signature, access));
            if (codeOff != 0 && item.calls.size() < MAX_CALLS_PER_CLASS) {
                String caller = item.descriptor + "->" + name + signature;
                try { parseCodeCalls(codeOff, caller, item); }
                catch (IOException malformedCode) {
                    // Keep the class/member index useful even when an OEM or obfuscated
                    // code_item is malformed; only its optional call edges are omitted.
                }
            }
        }
    }

    private void parseCodeCalls(int codeOffset, String caller, DexClass item) throws IOException {
        if ((codeOffset & 3) != 0) return;
        checkRange(codeOffset, 16);
        int units = u32(codeOffset + 12);
        if (units <= 0 || units > MAX_CODE_UNITS_PER_METHOD) return;
        int instructions = codeOffset + 16;
        checkRange(instructions, units * 2);
        for (int pc = 0; pc < units && item.calls.size() < MAX_CALLS_PER_CLASS
                && parsedCallEdges < MAX_CALLS_PER_DEX;) {
            int first = u16(instructions + pc * 2);
            int opcode = first & 0xff;
            if (opcode == 0x00) {
                int payload = first;
                int width = payloadWidth(payload, instructions, pc, units);
                pc += width > 0 ? width : 1;
                continue;
            }
            if (isMethodInvoke(opcode) && pc + 1 < units) {
                int referencedMethod = u16(instructions + (pc + 1) * 2);
                String callee = methodReference(referencedMethod);
                if (callee != null) {
                    item.calls.add(new CallSite(caller, callee, opcodeName(opcode)));
                    parsedCallEdges++;
                }
            }
            int width = instructionWidth(opcode);
            if (width < 1 || pc + width > units) break;
            pc += width;
        }
    }

    private int payloadWidth(int ident, int instructions, int pc, int totalUnits) throws IOException {
        if (ident == 0x0100) {
            if (pc + 2 > totalUnits) return 1;
            int size = u16(instructions + (pc + 1) * 2);
            long width = 4L + (long) size * 2L;
            return width <= totalUnits - pc ? (int) width : 1;
        }
        if (ident == 0x0200) {
            if (pc + 2 > totalUnits) return 1;
            int size = u16(instructions + (pc + 1) * 2);
            long width = 2L + (long) size * 4L;
            return width <= totalUnits - pc ? (int) width : 1;
        }
        if (ident == 0x0300) {
            if (pc + 4 > totalUnits) return 1;
            int elementWidth = u16(instructions + (pc + 1) * 2);
            long size = (u16(instructions + (pc + 2) * 2) & 0xffffL)
                    | ((u16(instructions + (pc + 3) * 2) & 0xffffL) << 16);
            if (elementWidth <= 0 || size > Integer.MAX_VALUE) return 1;
            long dataUnits = (size * elementWidth + 1L) / 2L;
            long width = 4L + dataUnits;
            return width <= totalUnits - pc ? (int) width : 1;
        }
        return 1;
    }

    private boolean isMethodInvoke(int opcode) {
        return (opcode >= 0x6e && opcode <= 0x72)
                || (opcode >= 0x74 && opcode <= 0x78)
                || opcode == 0xfa || opcode == 0xfb;
    }

    static int instructionWidth(int opcode) {
        // const-wide (format 51l) stores a 64-bit literal in four code units
        // following the opcode. Treating it as one unit desynchronizes every
        // subsequent instruction and can fabricate or miss invoke edges.
        if (opcode == 0x18) return 5;
        if ((opcode >= 0x02 && opcode <= 0x02)
                || opcode == 0x05 || opcode == 0x08
                || opcode == 0x13 || opcode == 0x15 || opcode == 0x16
                || opcode == 0x18 || opcode == 0x19 || opcode == 0x1a || opcode == 0x1c
                || opcode == 0x1f || opcode == 0x20 || opcode == 0x22 || opcode == 0x23
                || opcode == 0x29
                || (opcode >= 0x2d && opcode <= 0x3d)
                || (opcode >= 0x44 && opcode <= 0x6d)
                || (opcode >= 0xd0 && opcode <= 0xe2)
                || opcode == 0xfe || opcode == 0xff) return 2;
        if (opcode == 0x03 || opcode == 0x06 || opcode == 0x09
                || opcode == 0x14 || opcode == 0x17
                || opcode == 0x1b || opcode == 0x24 || opcode == 0x25 || opcode == 0x26
                || opcode == 0x2a || opcode == 0x2b || opcode == 0x2c
                || (opcode >= 0x6e && opcode <= 0x72)
                || (opcode >= 0x74 && opcode <= 0x78)
                // invoke-custom and invoke-custom/range reference call_site_ids, not method_ids,
                // but still occupy three code units and must not desynchronize the scan.
                || opcode == 0xfc || opcode == 0xfd) return 3;
        if (opcode == 0xfa || opcode == 0xfb) return 4;
        return 1;
    }

    private String opcodeName(int opcode) {
        switch (opcode) {
            case 0x6e: case 0x74: return "invoke-virtual";
            case 0x6f: case 0x75: return "invoke-super";
            case 0x70: case 0x76: return "invoke-direct";
            case 0x71: case 0x77: return "invoke-static";
            case 0x72: case 0x78: return "invoke-interface";
            case 0xfa: return "invoke-polymorphic";
            case 0xfb: return "invoke-polymorphic/range";
            default: return "invoke";
        }
    }

    private String methodReference(int index) throws IOException {
        if (index < 0 || index >= methodsSize) return null;
        int p = methodsOff + index * 8;
        String owner = type(u16(p));
        String name = string(u32(p + 4));
        String signature = proto(u16(p + 2));
        if (owner == null || name == null || signature == null) return null;
        return owner + "->" + name + signature;
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
        int utf16Length = readUleb(cursor);
        String value = decodeMutf8(data, cursor[0], utf16Length);
        stringCache[index] = value;
        return value;
    }

    /** Decode the DEX string_data_item MUTF-8 payload, whose length counts UTF-16 code units. */
    static String decodeMutf8(byte[] bytes, int offset, int utf16Length) throws IOException {
        if (bytes == null || offset < 0 || offset > bytes.length
                || utf16Length < 0 || utf16Length > bytes.length) {
            throw new IOException("invalid DEX MUTF-8 string bounds");
        }
        char[] decoded = new char[utf16Length];
        int cursor = offset;
        for (int i = 0; i < utf16Length; i++) {
            if (cursor >= bytes.length) throw new IOException("truncated DEX MUTF-8 string");
            int first = bytes[cursor++] & 0xff;
            if (first == 0) throw new IOException("DEX MUTF-8 terminator before declared UTF-16 length");
            if (first <= 0x7f) {
                decoded[i] = (char) first;
                continue;
            }
            if ((first & 0xe0) == 0xc0) {
                if (cursor >= bytes.length) throw new IOException("truncated DEX MUTF-8 two-byte sequence");
                int second = bytes[cursor++] & 0xff;
                if ((second & 0xc0) != 0x80) throw new IOException("invalid DEX MUTF-8 continuation byte");
                int value = ((first & 0x1f) << 6) | (second & 0x3f);
                if (value < 0x80 && value != 0) throw new IOException("overlong DEX MUTF-8 two-byte sequence");
                decoded[i] = (char) value;
                continue;
            }
            if ((first & 0xf0) == 0xe0) {
                if (cursor > bytes.length - 2) throw new IOException("truncated DEX MUTF-8 three-byte sequence");
                int second = bytes[cursor++] & 0xff;
                int third = bytes[cursor++] & 0xff;
                if ((second & 0xc0) != 0x80 || (third & 0xc0) != 0x80)
                    throw new IOException("invalid DEX MUTF-8 continuation bytes");
                int value = ((first & 0x0f) << 12) | ((second & 0x3f) << 6) | (third & 0x3f);
                if (value < 0x800) throw new IOException("overlong DEX MUTF-8 three-byte sequence");
                // Supplementary Unicode values are represented by a UTF-16 surrogate pair,
                // each encoded as its own three-byte MUTF-8 sequence.
                decoded[i] = (char) value;
                continue;
            }
            throw new IOException("invalid DEX MUTF-8 leading byte");
        }
        if (cursor >= bytes.length || bytes[cursor] != 0)
            throw new IOException("DEX MUTF-8 terminator missing at declared UTF-16 length");
        return new String(decoded);
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

    private long u32Bits(int offset) throws IOException {
        checkRange(offset, 4);
        return (data[offset] & 0xffL)
                | ((data[offset + 1] & 0xffL) << 8)
                | ((data[offset + 2] & 0xffL) << 16)
                | ((data[offset + 3] & 0xffL) << 24);
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
