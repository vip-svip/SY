package de.privacyguard.adhook.imported.shield;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/** Private-file storage for arbitrarily sized, user-confirmed cleanup queues. */
final class FxYulongCleanupQueueStore {
    private static final String PREFIX = "fx-yulong-cleanup-";

    static final class QueueData {
        final ArrayList<String> packages = new ArrayList<>();
        final ArrayList<String> labels = new ArrayList<>();
        final ArrayList<String> reasons = new ArrayList<>();
        final Set<String> removed = new HashSet<>();
        int index;
    }

    private FxYulongCleanupQueueStore() { }

    static String create(Context context, List<String> packageNames,
                         List<String> appLabels, List<String> appReasons) throws IOException {
        if (packageNames == null || appLabels == null || appReasons == null
                || packageNames.isEmpty()
                || appLabels.size() != packageNames.size()
                || appReasons.size() != packageNames.size()) {
            throw new IOException("批量清理队列字段缺失或数量不一致");
        }
        QueueData data = new QueueData();
        Set<String> unique = new HashSet<>();
        for (int i = 0; i < packageNames.size(); i++) {
            String pkg = packageNames.get(i);
            if (pkg == null || !pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                    || !unique.add(pkg)) {
                throw new IOException("批量清理队列包含无效或重复包名");
            }
            data.packages.add(pkg);
            String label = appLabels.get(i);
            data.labels.add(label == null || label.trim().isEmpty() ? pkg : label);
            data.reasons.add(appReasons.get(i) == null ? "" : appReasons.get(i));
        }
        String id = UUID.randomUUID().toString();
        save(context, id, data);
        return id;
    }

    static QueueData load(Context context, String id) throws IOException {
        File source = file(context, id);
        if (!source.isFile() || Files.isSymbolicLink(source.toPath())) {
            throw new IOException("批量清理队列文件不存在或不可用");
        }
        byte[] bytes = Files.readAllBytes(source.toPath());
        final JSONObject root;
        try {
            root = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        } catch (Exception malformed) {
            throw new IOException("批量清理队列文件格式无效", malformed);
        }
        JSONArray packageArray = root.optJSONArray("packages");
        JSONArray labelArray = root.optJSONArray("labels");
        JSONArray reasonArray = root.optJSONArray("reasons");
        JSONArray removedArray = root.optJSONArray("removed");
        if (packageArray == null || labelArray == null || reasonArray == null
                || packageArray.length() == 0
                || labelArray.length() != packageArray.length()
                || reasonArray.length() != packageArray.length()) {
            throw new IOException("批量清理队列字段缺失或数量不一致");
        }

        QueueData data = new QueueData();
        Set<String> unique = new HashSet<>();
        for (int i = 0; i < packageArray.length(); i++) {
            String pkg = packageArray.optString(i, null);
            String label = labelArray.optString(i, null);
            String reason = reasonArray.optString(i, null);
            if (pkg == null || !pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                    || !unique.add(pkg) || label == null || reason == null) {
                throw new IOException("批量清理队列包含无效、重复或不完整数据");
            }
            data.packages.add(pkg);
            data.labels.add(label);
            data.reasons.add(reason);
        }
        if (removedArray != null) {
            for (int i = 0; i < removedArray.length(); i++) {
                String pkg = removedArray.optString(i, null);
                if (pkg == null || !unique.contains(pkg)) {
                    throw new IOException("批量清理队列已移除状态与队列不匹配");
                }
                data.removed.add(pkg);
            }
        }
        data.index = root.optInt("index", 0);
        if (data.index < 0 || data.index > data.packages.size()) {
            throw new IOException("批量清理队列当前位置无效");
        }
        return data;
    }

    static void save(Context context, String id, QueueData data) throws IOException {
        if (data == null || data.packages.isEmpty()
                || data.labels.size() != data.packages.size()
                || data.reasons.size() != data.packages.size()
                || data.index < 0 || data.index > data.packages.size()) {
            throw new IOException("拒绝保存不完整的批量清理队列");
        }
        JSONObject root = new JSONObject();
        JSONArray packageArray = new JSONArray();
        JSONArray labelArray = new JSONArray();
        JSONArray reasonArray = new JSONArray();
        JSONArray removedArray = new JSONArray();
        try {
            Set<String> unique = new HashSet<>();
            for (int i = 0; i < data.packages.size(); i++) {
                String pkg = data.packages.get(i);
                if (pkg == null || !pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                        || !unique.add(pkg)) {
                    throw new IOException("批量清理队列包含无效或重复包名");
                }
                packageArray.put(pkg);
                labelArray.put(data.labels.get(i) == null ? pkg : data.labels.get(i));
                reasonArray.put(data.reasons.get(i) == null ? "" : data.reasons.get(i));
            }
            for (String pkg : data.removed) {
                if (!unique.contains(pkg)) throw new IOException("已移除项目不属于当前批量清理队列");
                removedArray.put(pkg);
            }
            root.put("packages", packageArray);
            root.put("labels", labelArray);
            root.put("reasons", reasonArray);
            root.put("removed", removedArray);
            root.put("index", data.index);
        } catch (org.json.JSONException invalid) {
            throw new IOException("无法序列化批量清理队列", invalid);
        }

        File target = file(context, id);
        File parent = target.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("无法创建批量清理私有目录");
        }
        File temp = new File(parent, target.getName() + ".tmp");
        byte[] encoded = root.toString().getBytes(StandardCharsets.UTF_8);
        try (FileOutputStream output = new FileOutputStream(temp, false)) {
            output.write(encoded);
            output.flush();
            output.getFD().sync();
        }
        try {
            Files.move(temp.toPath(), target.toPath(),
                    StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException atomicFailure) {
            try {
                Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING);
            } catch (IOException replaceFailure) {
                replaceFailure.addSuppressed(atomicFailure);
                throw replaceFailure;
            }
        } finally {
            if (temp.exists()) temp.delete();
        }
    }

    static void delete(Context context, String id) {
        try {
            File target = file(context, id);
            File temp = new File(target.getParentFile(), target.getName() + ".tmp");
            if (temp.isFile()) temp.delete();
            if (target.isFile() && !Files.isSymbolicLink(target.toPath())) target.delete();
        } catch (IOException ignored) { }
    }

    private static File file(Context context, String id) throws IOException {
        if (context == null || id == null || !id.matches("[0-9a-fA-F-]{36}")) {
            throw new IOException("批量清理队列标识无效");
        }
        return new File(context.getFilesDir(), PREFIX + id + ".json");
    }
}
