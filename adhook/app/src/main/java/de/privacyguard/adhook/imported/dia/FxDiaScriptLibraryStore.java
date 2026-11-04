package de.privacyguard.adhook.imported.dia;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/**
 * Persistent store shared with the existing Frida manager page.
 * It deliberately retains the original preference file and JSON schema.
 */
public final class FxDiaScriptLibraryStore {
    public static final String PREFS = "fx_dia_frida";
    public static final String KEY = "frida_script_library_v1";
    public static final String SCHEMA = "FX-DIA-FRIDA-SCRIPTS-1";
    private static final Object LOCK = new Object();

    public static final class ImportPreview {
        public final int count;
        public final List<String> overwrittenNames;

        ImportPreview(int count, List<String> overwrittenNames) {
            this.count = count;
            this.overwrittenNames = overwrittenNames;
        }
    }

    private FxDiaScriptLibraryStore() { }

    public static JSONObject read(Context context) throws Exception {
        if (context == null) throw new IllegalArgumentException("Context 为空。");
        synchronized (LOCK) {
            return readLocked(context);
        }
    }

    private static JSONObject readLocked(Context context) throws Exception {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String raw = prefs.getString(KEY, "{}");
        if (raw == null || raw.isEmpty()) return new JSONObject();
        if (raw.getBytes(StandardCharsets.UTF_8).length
                > FxDiaScriptLibraryPolicy.MAX_LIBRARY_JSON_BYTES) {
            throw new IllegalStateException("Frida 脚本库超过 1 MiB，拒绝加载。");
        }
        JSONObject root = new JSONObject(raw);
        String schema = root.optString("schema", "");
        if (!schema.isEmpty() && !SCHEMA.equals(schema)) {
            throw new IllegalArgumentException("本机脚本库 schema 不受支持。");
        }
        JSONObject scripts = root.optJSONObject("scripts");
        if (scripts == null) {
            if (root.length() == 0) return new JSONObject();
            throw new IllegalArgumentException("本机脚本库缺少 scripts 对象。");
        }
        validateScripts(scripts);
        return scripts;
    }

    public static void save(Context context, String rawName, String source) throws Exception {
        String name = FxDiaScriptLibraryPolicy.normalizeName(rawName);
        String nameError = FxDiaScriptLibraryPolicy.validateName(name);
        if (nameError != null) throw new IllegalArgumentException(nameError);
        String sourceError = FxDiaScriptLibraryPolicy.validateSource(source);
        if (sourceError != null) throw new IllegalArgumentException(sourceError);
        synchronized (LOCK) {
            JSONObject scripts = readLocked(context);
            boolean exists = scripts.has(name);
            String countError = FxDiaScriptLibraryPolicy.validateCount(scripts.length(), exists);
            if (countError != null) throw new IllegalArgumentException(countError);
            scripts.put(name, source);
            writeLocked(context, scripts);
        }
    }

    /** Replace all entries after the caller has explicitly confirmed an import/merge. */
    public static void replaceAll(Context context, JSONObject scripts) throws Exception {
        if (context == null) throw new IllegalArgumentException("Context 为空。");
        synchronized (LOCK) {
            writeLocked(context, scripts);
        }
    }

    public static void delete(Context context, String name) throws Exception {
        if (context == null || name == null) throw new IllegalArgumentException("删除参数无效。");
        synchronized (LOCK) {
            JSONObject scripts = readLocked(context);
            scripts.remove(name);
            writeLocked(context, scripts);
        }
    }

    public static String exportJson(Context context) throws Exception {
        synchronized (LOCK) {
            JSONObject root = new JSONObject();
            root.put("schema", SCHEMA);
            root.put("scripts", readLocked(context));
            String json = root.toString(2);
            if (json.getBytes(StandardCharsets.UTF_8).length
                    > FxDiaScriptLibraryPolicy.MAX_LIBRARY_JSON_BYTES) {
                throw new IllegalStateException("Frida 脚本库 JSON 超过 1 MiB，无法导出。");
            }
            return json;
        }
    }

    public static ImportPreview previewImport(Context context, String json) throws Exception {
        JSONObject incoming = parseImport(json);
        JSONObject existing;
        synchronized (LOCK) {
            existing = readLocked(context);
        }
        List<String> overlaps = new ArrayList<>();
        Iterator<String> keys = incoming.keys();
        while (keys.hasNext()) {
            String name = keys.next();
            if (existing.has(name)) overlaps.add(name);
        }
        return new ImportPreview(incoming.length(), overlaps);
    }

    /** Merge is called only after the UI has explicitly described same-name replacement. */
    public static int mergeImport(Context context, String json) throws Exception {
        JSONObject incoming = parseImport(json);
        synchronized (LOCK) {
            JSONObject merged = readLocked(context);
            Iterator<String> keys = incoming.keys();
            while (keys.hasNext()) {
                String name = keys.next();
                merged.put(name, incoming.getString(name));
            }
            writeLocked(context, merged);
        }
        return incoming.length();
    }

    private static JSONObject parseImport(String json) throws Exception {
        if (json == null || json.getBytes(StandardCharsets.UTF_8).length == 0
                || json.getBytes(StandardCharsets.UTF_8).length
                > FxDiaScriptLibraryPolicy.MAX_LIBRARY_JSON_BYTES) {
            throw new IllegalArgumentException("Frida 脚本库 JSON 为空或超过 1 MiB。");
        }
        JSONObject root = new JSONObject(json);
        if (!SCHEMA.equals(root.optString("schema", ""))) {
            throw new IllegalArgumentException("JSON schema 不匹配。");
        }
        JSONObject incoming = root.getJSONObject("scripts");
        if (incoming.length() > FxDiaScriptLibraryPolicy.MAX_SCRIPTS) {
            throw new IllegalArgumentException("单次最多导入 64 个脚本。");
        }
        validateScripts(incoming);
        return incoming;
    }

    private static void validateScripts(JSONObject scripts) {
        if (scripts == null || scripts.length() > FxDiaScriptLibraryPolicy.MAX_SCRIPTS) {
            throw new IllegalArgumentException("脚本库最多保存 64 个脚本。");
        }
        Iterator<String> keys = scripts.keys();
        while (keys.hasNext()) {
            String name = keys.next();
            String nameError = FxDiaScriptLibraryPolicy.validateName(name);
            Object rawSource = scripts.opt(name);
            if (!(rawSource instanceof String)) {
                throw new IllegalArgumentException("脚本“" + name + "”的内容必须是字符串。");
            }
            String sourceError = FxDiaScriptLibraryPolicy.validateSource((String) rawSource);
            if (nameError != null) throw new IllegalArgumentException(nameError);
            if (sourceError != null) throw new IllegalArgumentException("脚本“" + name + "”： " + sourceError);
        }
    }

    private static void writeLocked(Context context, JSONObject scripts) throws Exception {
        validateScripts(scripts);
        JSONObject root = new JSONObject();
        root.put("schema", SCHEMA);
        root.put("scripts", scripts);
        String raw = root.toString();
        if (raw.getBytes(StandardCharsets.UTF_8).length
                > FxDiaScriptLibraryPolicy.MAX_LIBRARY_JSON_BYTES) {
            throw new IllegalArgumentException("Frida 脚本库超过 1 MiB，请删除部分脚本。");
        }
        boolean saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY, raw).commit();
        if (!saved) throw new IllegalStateException("Android 没有确认脚本库写入成功。");
    }
}
