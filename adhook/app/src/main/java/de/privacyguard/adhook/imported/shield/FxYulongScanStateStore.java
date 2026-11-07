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
import java.util.Set;
import java.util.UUID;

/** Private-file persistence for complete Shield scan findings and selection state. */
final class FxYulongScanStateStore {
    private static final String PREFIX = "fx-yulong-scan-";

    static final class ScanData {
        final ArrayList<FxYulongScanEngine.Finding> findings = new ArrayList<>();
        final Set<String> selectedPackages = new HashSet<>();
        String status = "";
        boolean complete;
    }

    private FxYulongScanStateStore() { }

    static String createId() {
        return UUID.randomUUID().toString();
    }

    static ScanData load(Context context, String id) throws IOException {
        File source = file(context, id);
        if (!source.isFile() || Files.isSymbolicLink(source.toPath())) {
            throw new IOException("扫描状态文件不存在或不可用");
        }
        final JSONObject root;
        try {
            root = new JSONObject(new String(Files.readAllBytes(source.toPath()), StandardCharsets.UTF_8));
        } catch (Exception malformed) {
            throw new IOException("扫描状态文件格式无效", malformed);
        }
        JSONArray findings = root.optJSONArray("findings");
        JSONArray selected = root.optJSONArray("selected");
        if (findings == null) throw new IOException("扫描状态缺少完整命中列表");

        ScanData data = new ScanData();
        data.status = root.optString("status", "");
        data.complete = root.optBoolean("complete", false);
        Set<String> packages = new HashSet<>();
        for (int i = 0; i < findings.length(); i++) {
            JSONObject item = findings.optJSONObject(i);
            if (item == null) throw new IOException("扫描命中项目格式无效");
            String pkg = item.optString("package", null);
            String label = item.optString("label", null);
            String severityRaw = item.optString("severity", null);
            String reason = item.optString("reason", null);
            String sourceLabel = item.optString("source", "");
            String matchedEntry = item.optString("matched", "");
            if (pkg == null || !pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                    || !packages.add(pkg) || label == null || severityRaw == null || reason == null) {
                throw new IOException("扫描命中项目包含无效或重复数据");
            }
            final FxYulongScanEngine.Severity severity;
            try {
                severity = FxYulongScanEngine.Severity.valueOf(severityRaw);
            } catch (RuntimeException invalid) {
                throw new IOException("扫描命中风险等级无效", invalid);
            }
            data.findings.add(new FxYulongScanEngine.Finding(
                    pkg, label, severity, reason, sourceLabel, matchedEntry));
        }
        if (selected != null) {
            for (int i = 0; i < selected.length(); i++) {
                String pkg = selected.optString(i, null);
                if (pkg == null || !packages.contains(pkg)) {
                    throw new IOException("已选择项目不属于当前扫描命中列表");
                }
                data.selectedPackages.add(pkg);
            }
        }
        return data;
    }

    static void save(Context context, String id, ScanData data) throws IOException {
        if (data == null) throw new IOException("扫描状态为空");
        JSONObject root = new JSONObject();
        JSONArray findings = new JSONArray();
        JSONArray selected = new JSONArray();
        try {
            Set<String> packages = new HashSet<>();
            for (FxYulongScanEngine.Finding finding : data.findings) {
                if (finding == null || finding.packageName == null
                        || !finding.packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                        || !packages.add(finding.packageName)
                        || finding.label == null || finding.severity == null
                        || finding.reason == null) {
                    throw new IOException("扫描命中列表包含无效或重复项目");
                }
                JSONObject item = new JSONObject();
                item.put("package", finding.packageName);
                item.put("label", finding.label);
                item.put("severity", finding.severity.name());
                item.put("reason", finding.reason);
                item.put("source", finding.sourceLabel == null ? "" : finding.sourceLabel);
                item.put("matched", finding.matchedEntry == null ? "" : finding.matchedEntry);
                findings.put(item);
            }
            for (String pkg : data.selectedPackages) {
                if (!packages.contains(pkg)) throw new IOException("选中项目不属于扫描命中列表");
                selected.put(pkg);
            }
            root.put("findings", findings);
            root.put("selected", selected);
            root.put("status", data.status == null ? "" : data.status);
            root.put("complete", data.complete);
        } catch (org.json.JSONException invalid) {
            throw new IOException("无法序列化扫描状态", invalid);
        }

        File target = file(context, id);
        File parent = target.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("无法创建扫描状态私有目录");
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
            throw new IOException("扫描状态标识无效");
        }
        return new File(context.getFilesDir(), PREFIX + id + ".json");
    }
}
