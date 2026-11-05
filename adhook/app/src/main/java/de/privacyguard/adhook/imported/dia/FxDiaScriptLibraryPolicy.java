package de.privacyguard.adhook.imported.dia;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;

/** Validation rules shared by the native Dia Frida script-library page. */
public final class FxDiaScriptLibraryPolicy {
    private FxDiaScriptLibraryPolicy() { }

    /** Decode imported JSON without silently replacing malformed UTF-8 bytes. */
    public static String decodeUtf8(byte[] bytes) {
        if (bytes == null) throw new IllegalArgumentException("JSON 数据为空。");
        try {
            String decoded = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString();
            // Local SAF files commonly carry a UTF-8 BOM; JSON parsers may ignore it.
            return !decoded.isEmpty() && decoded.charAt(0) == 0xFEFF
                    ? decoded.substring(1) : decoded;
        } catch (CharacterCodingException malformed) {
            throw new IllegalArgumentException("JSON 文件不是有效的 UTF-8 编码。", malformed);
        }
    }

    public static String normalizeName(String raw) {
        return raw == null ? "" : raw.trim();
    }

    public static String validateName(String raw) {
        String name = normalizeName(raw);
        if (name.isEmpty()) return "脚本名称不能为空。";
        if (name.indexOf('|') >= 0) return "脚本名称不能包含竖线字符。";
        for (int i = 0; i < name.length(); i++) {
            if (Character.isISOControl(name.charAt(i))) {
                return "脚本名称不能包含换行或控制字符。";
            }
        }
        return null;
    }

    public static String validateSource(String source) {
        if (source == null || source.trim().isEmpty()) return "脚本内容不能为空。";
        return null;
    }

}
