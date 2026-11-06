package de.privacyguard.adhook.imported.dia;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONException;
import org.json.JSONObject;

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
        if (context == null) throw new IllegalArgumentException("Context 为空。");
        String name = FxDiaScriptLibraryPolicy.normalizeName(rawName);
        String nameError = FxDiaScriptLibraryPolicy.validateName(name);
        if (nameError != null) throw new IllegalArgumentException(nameError);
        String sourceError = FxDiaScriptLibraryPolicy.validateSource(source);
        if (sourceError != null) throw new IllegalArgumentException(sourceError);
        synchronized (LOCK) {
            JSONObject scripts = readLocked(context);
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

    /** Delete a user-confirmed group of script names in one atomic preference write. */
    public static int deleteMany(Context context, List<String> names) throws Exception {
        if (context == null || names == null) throw new IllegalArgumentException("批量删除参数无效。");
        synchronized (LOCK) {
            JSONObject scripts = readLocked(context);
            int removed = 0;
            for (String name : names) {
                if (name == null) continue;
                if (scripts.has(name)) {
                    scripts.remove(name);
                    removed++;
                }
            }
            if (removed > 0) writeLocked(context, scripts);
            return removed;
        }
    }

    /** Export only the supplied existing names while retaining the shared import schema. */
    public static String exportJson(Context context, List<String> names) throws Exception {
        if (context == null || names == null) throw new IllegalArgumentException("导出参数无效。");
        synchronized (LOCK) {
            JSONObject all = readLocked(context);
            JSONObject selected = new JSONObject();
            for (String name : names) {
                if (name != null && all.has(name)) selected.put(name, all.getString(name));
            }
            JSONObject root = new JSONObject();
            root.put("schema", SCHEMA);
            root.put("scripts", selected);
            return root.toString(2);
        }
    }

    public static String exportJson(Context context) throws Exception {
        if (context == null) throw new IllegalArgumentException("Context 为空。");
        synchronized (LOCK) {
            JSONObject root = new JSONObject();
            root.put("schema", SCHEMA);
            root.put("scripts", readLocked(context));
            return root.toString(2);
        }
    }

    public static ImportPreview previewImport(Context context, String json) throws Exception {
        if (context == null) throw new IllegalArgumentException("Context 为空。");
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
        return mergeImport(context, json, java.util.Collections.emptyList());
    }

    /**
     * Merge only names the user explicitly confirmed after previewImport().
     * Re-check overlaps under the write lock so a new same-name entry cannot be
     * silently overwritten between preview and commit.
     */
    public static int mergeImport(Context context, String json, List<String> confirmedOverwrites) throws Exception {
        if (context == null) throw new IllegalArgumentException("Context 为空。");
        List<String> confirmed = confirmedOverwrites == null
                ? java.util.Collections.emptyList() : confirmedOverwrites;
        JSONObject incoming = parseImport(json);
        synchronized (LOCK) {
            JSONObject merged = readLocked(context);
            List<String> unconfirmed = new ArrayList<>();
            Iterator<String> keys = incoming.keys();
            while (keys.hasNext()) {
                String name = keys.next();
                if (merged.has(name) && !confirmed.contains(name)) unconfirmed.add(name);
            }
            if (!unconfirmed.isEmpty()) {
                throw new IllegalStateException("脚本库在预览后发生变化，出现未确认的同名脚本："
                        + android.text.TextUtils.join("、", unconfirmed) + "。请重新预览后再导入。");
            }
            keys = incoming.keys();
            while (keys.hasNext()) {
                String name = keys.next();
                merged.put(name, incoming.getString(name));
            }
            writeLocked(context, merged);
        }
        return incoming.length();
    }

    private static JSONObject parseImport(String json) throws Exception {
        if (json == null || json.isEmpty()) {
            throw new IllegalArgumentException("Frida 脚本库 JSON 为空。");
        }
        JSONObject root = new JSONObject(json);
        if (!SCHEMA.equals(root.optString("schema", ""))) {
            throw new IllegalArgumentException("JSON schema 不匹配。");
        }
        JSONObject incoming = root.getJSONObject("scripts");
        validateScripts(incoming);
        return incoming;
    }

    private static void validateScripts(JSONObject scripts) {
        if (scripts == null) {
            throw new IllegalArgumentException("脚本库对象为空。");
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
        boolean saved = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY, raw).commit();
        if (!saved) throw new IllegalStateException("Android 没有确认脚本库写入成功。");
    }
}
