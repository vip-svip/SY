package de.privacyguard.adhook.imported.dia;

import java.nio.charset.StandardCharsets;

/** Validation rules shared by the native Dia Frida script-library page. */
public final class FxDiaScriptLibraryPolicy {
    public static final int MAX_NAME_CHARS = 64;
    public static final int MAX_SOURCE_BYTES = 128 * 1024;
    public static final int MAX_SCRIPTS = 64;
    public static final int MAX_LIBRARY_JSON_BYTES = 1024 * 1024;

    private FxDiaScriptLibraryPolicy() { }

    public static String normalizeName(String raw) {
        return raw == null ? "" : raw.trim();
    }

    public static String validateName(String raw) {
        String name = normalizeName(raw);
        if (name.isEmpty()) return "脚本名称不能为空。";
        if (name.length() > MAX_NAME_CHARS) return "脚本名称不能超过 64 个字符。";
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
        if (source.getBytes(StandardCharsets.UTF_8).length > MAX_SOURCE_BYTES) {
            return "单个脚本不能超过 128 KiB。";
        }
        return null;
    }

    public static String validateCount(int currentCount, boolean replacingExisting) {
        if (currentCount < 0 || currentCount > MAX_SCRIPTS) return "脚本库数量无效。";
        if (!replacingExisting && currentCount >= MAX_SCRIPTS) {
            return "脚本库最多保存 64 个脚本，请先删除旧脚本。";
        }
        return null;
    }
}
