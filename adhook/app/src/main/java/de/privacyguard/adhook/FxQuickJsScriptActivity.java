package de.privacyguard.adhook;

import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.util.Base64;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.imported.ad.FxYulongRootModuleCommand;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native UI for the module-owned QuickJS script list and local runner. */
public final class FxQuickJsScriptActivity extends FxNativeTabActivity {
    private static final int REQUEST_IMPORT_SCRIPT = 0x5f31;
    private static final int REQUEST_IMPORT_SCRIPT_CONFIG = 0x5f32;
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "fx-quickjs-native-ui");
        thread.setDaemon(true);
        return thread;
    });
    private final List<ScriptItem> scripts = new ArrayList<>();
    private LinearLayout rows;
    private TextView status;
    private TextView schedulerStatus;
    private Button importLocal;
    private Button addSubscription;
    private Button importConfig;
    private Button openDiaScripts;
    private Button syncSubscriptions;
    private Button schedulerButton;
    private Button refreshButton;
    private boolean busy;
    private boolean schedulerRunning;

    private static final class ScriptItem {
        final int index;
        final String name;
        final String type;
        final String hash;
        final long bytes;
        final boolean enabled;

        ScriptItem(int index, String name, String type, String hash, long bytes, boolean enabled) {
            this.index = index;
            this.name = name;
            this.type = type;
            this.hash = hash;
            this.bytes = bytes;
            this.enabled = enabled;
        }

        boolean local() { return "本地 QuickJS".equals(type); }
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setTag("fx-page-root");
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(14), dp(10), dp(14), dp(16));

        LinearLayout header = new LinearLayout(this);
        header.setTag("fx-toolbar");
        header.setGravity(Gravity.CENTER_VERTICAL);
        Button back = button("‹ 返回脚本", this::finish);
        back.setTag("fx-toolbar-action");
        header.addView(back);
        TextView title = new TextView(this);
        title.setTag("fx-toolbar-title");
        title.setText("脚本 · QuickJS 运行时");
        title.setTextSize(19);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        status = text("正在读取 QuickJS 脚本清单…", 12, false); status.setTag("fx-loading-state");
        root.addView(status);
        schedulerStatus = text("自动刷新状态读取中…", 12, false); schedulerStatus.setTag("fx-card-detail");
        root.addView(schedulerStatus);

        LinearLayout actions = new LinearLayout(this);
        actions.setTag("fx-action-row");
        actions.setGravity(Gravity.CENTER_VERTICAL);
        importLocal = button("导入本地 JS", this::chooseLocalScript);
        addSubscription = button("添加 HTTPS 订阅", this::showAddSubscriptionDialog);
        actions.addView(importLocal, new LinearLayout.LayoutParams(0, dp(48), 1));
        actions.addView(addSubscription, new LinearLayout.LayoutParams(0, dp(48), 1));
        root.addView(actions);

        LinearLayout importActions = new LinearLayout(this);
        importActions.setTag("fx-action-row");
        importActions.setGravity(Gravity.CENTER_VERTICAL);
        importConfig = button("导入配置文件", this::chooseConfigFile);
        openDiaScripts = button("Dia / Frida 脚本库", () -> startActivity(
                new Intent(this, de.privacyguard.adhook.imported.dia.FxDiaScriptLibraryActivity.class)));
        importActions.addView(importConfig, new LinearLayout.LayoutParams(0, dp(48), 1));
        importActions.addView(openDiaScripts, new LinearLayout.LayoutParams(0, dp(48), 1));
        root.addView(importActions);

        LinearLayout operations = new LinearLayout(this);
        operations.setTag("fx-action-row");
        operations.setGravity(Gravity.CENTER_VERTICAL);
        syncSubscriptions = button("立即同步", () -> perform("sync"));
        schedulerButton = button("启用自动刷新", this::toggleScheduler);
        refreshButton = button("刷新列表", this::reload);
        operations.addView(syncSubscriptions, new LinearLayout.LayoutParams(0, dp(48), 1));
        operations.addView(schedulerButton, new LinearLayout.LayoutParams(0, dp(48), 1));
        operations.addView(refreshButton, new LinearLayout.LayoutParams(0, dp(48), 1));
        root.addView(operations);

        TextView note = text("本地 JS 由 FX QuickJS-NG 执行。运行前会再次核对脚本 SHA-256；脚本可访问其宿主接口，请只运行可信来源。支持导入 Surge / Loon / Quantumult X 配置及 Egern / Stash YAML 中受支持的 HTTPS HTTP 脚本；Dia Frida 脚本库单独保留。", 11, false); note.setTag("fx-card-detail");
        note.setPadding(0, dp(6), 0, dp(12));
        root.addView(note);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        rows = new LinearLayout(this); rows.setTag("fx-card-group");
        rows.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(rows);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 3);
        reload();
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(0xff263344);
        if (bold) view.setTypeface(null, android.graphics.Typeface.BOLD);
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setTag("fx-action-row");
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private String shellQuote(String value) {
        return "'" + value.replace("'", "'\''") + "'";
    }

    private String command(String... arguments) {
        StringBuilder value = new StringBuilder(
                FxYulongRootModuleCommand.prefix("native-jsruntime-control.sh"))
                .append("MP=\"$MP\" PG='/data/adb/privacyguard' ")
                .append("sh \"$MP/scripts/native-jsruntime-control.sh\"");
        for (String argument : arguments) value.append(' ').append(shellQuote(argument));
        return value.toString();
    }

    private String decodeNote(String value) {
        try {
            return new String(Base64.decode(value, Base64.DEFAULT), StandardCharsets.UTF_8);
        } catch (Exception error) {
            return "未命名脚本";
        }
    }

    private void reload() {
        if (busy || isFinishing() || isDestroyed()) return;
        busy = true;
        setControlsEnabled();
        status.setText("正在读取 QuickJS 脚本清单…");
        worker.execute(() -> {
            File snapshot = new File(getCacheDir(), "fx-quickjs-script-list.snapshot");
            RootAccess.Result listResult = RootAccess.executeToFile(command("list"), 60000L, snapshot);
            RootAccess.Result schedulerResult = RootAccess.execute(command("scheduler", "status"), 30000L, 4096);
            List<ScriptItem> loaded = new ArrayList<>();
            String failure = null;
            if (listResult.exitCode == 0 && snapshot.isFile()) {
                try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                        new FileInputStream(snapshot), StandardCharsets.UTF_8))) {
                    if (!"FXJS1".equals(reader.readLine())) {
                        failure = message(listResult);
                    } else {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            String[] f = line.split("\\|", -1);
                            try {
                                if (f.length == 6 && "L".equals(f[0])) {
                                    loaded.add(new ScriptItem(Integer.parseInt(f[1]),
                                            decodeNote(f[2]), "本地 QuickJS", f[3],
                                            Long.parseLong(f[4]), "1".equals(f[5])));
                                } else if (f.length == 5 && "U".equals(f[0])) {
                                    loaded.add(new ScriptItem(Integer.parseInt(f[1]),
                                            decodeNote(f[3]) + " · " + f[2], "HTTPS 订阅",
                                            "", 0L, "1".equals(f[4])));
                                } else if (f.length == 4 && "E".equals(f[0])) {
                                    loaded.add(new ScriptItem(Integer.parseInt(f[1]),
                                            decodeNote(f[2]), "内容损坏/格式未知", "",
                                            0L, "1".equals(f[3])));
                                }
                            } catch (NumberFormatException ignored) {
                                // A malformed row is never exposed as an executable item.
                            }
                        }
                    }
                } catch (Exception error) {
                    failure = error.getClass().getSimpleName() + ": " + error.getMessage();
                }
            } else {
                failure = message(listResult);
            }
            snapshot.delete();
            boolean scheduler = schedulerResult.exitCode == 0
                    && schedulerResult.output != null
                    && schedulerResult.output.contains("running=1");
            final String loadFailure = failure;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                busy = false;
                scripts.clear();
                scripts.addAll(loaded);
                schedulerRunning = scheduler;
                schedulerStatus.setText(scheduler
                        ? "自动刷新：运行中"
                        : "自动刷新：已停止");
                schedulerButton.setText(scheduler ? "停止自动刷新" : "启用自动刷新");
                if (loadFailure == null) {
                    status.setText("QuickJS 脚本 " + scripts.size() + " 项 · 本地可运行 "
                            + countLocalEnabled() + " 项");
                } else {
                    status.setText("脚本清单读取失败：" + loadFailure);
                }
                renderRows();
                setControlsEnabled();
            });
        });
    }

    private int countLocalEnabled() {
        int count = 0;
        for (ScriptItem item : scripts) if (item.local() && item.enabled && !item.hash.isEmpty()) count++;
        return count;
    }

    private void renderRows() {
        rows.removeAllViews();
        if (scripts.isEmpty()) {
            TextView empty = text("暂无 QuickJS 脚本。可导入本地 JavaScript，或添加 HTTPS 脚本订阅。", 13, false); empty.setTag("fx-card-detail");
            empty.setPadding(dp(8), dp(16), dp(8), dp(16));
            rows.addView(empty);
            return;
        }
        for (ScriptItem item : scripts) {
            LinearLayout card = new LinearLayout(this); card.setTag("fx-card");
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(10), dp(8), dp(10), dp(8));
            card.setBackgroundColor(0xfff0f3f7);
            LinearLayout.LayoutParams cardParams = new LinearLayout.LayoutParams(-1, -2);
            cardParams.setMargins(0, dp(4), 0, dp(4));
            TextView heading = text(item.name, 14, true); heading.setTag("fx-card-title");
            card.addView(heading);
            String state = item.enabled ? "启用" : "停用";
            String description = item.type + " · " + state;
            if (item.local()) description += " · " + item.bytes + " bytes";
            TextView detail = text(description, 11, false); detail.setTag("fx-card-detail"); card.addView(detail);
            LinearLayout actionRow = new LinearLayout(this); actionRow.setTag("fx-card-group");
            actionRow.setGravity(Gravity.CENTER_VERTICAL);
            if (item.local() && item.enabled && !item.hash.isEmpty()) {
                actionRow.addView(button("运行", () -> confirmRun(item)),
                        new LinearLayout.LayoutParams(0, dp(44), 1));
            }
            actionRow.addView(button(item.enabled ? "停用" : "启用",
                    () -> perform("toggle", String.valueOf(item.index), item.enabled ? "0" : "1")),
                    new LinearLayout.LayoutParams(0, dp(44), 1));
            actionRow.addView(button("删除", () -> confirmDelete(item)),
                    new LinearLayout.LayoutParams(0, dp(44), 1));
            card.addView(actionRow);
            rows.addView(card, cardParams);
        }
    }

    private void confirmRun(ScriptItem item) {
        fxDialogBuilder().setTitle("运行本地 QuickJS 脚本？")
                .setMessage("脚本：" + item.name + "\n\n脚本会在 FX QuickJS 宿主环境中执行。请确认来源可信。")
                .setNegativeButton("取消", null)
                .setPositiveButton("运行", (dialog, which) ->
                        perform("run", String.valueOf(item.index), item.hash))
                .show();
    }

    private void confirmDelete(ScriptItem item) {
        fxDialogBuilder().setTitle("删除脚本？")
                .setMessage(item.name)
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) ->
                        perform("delete", String.valueOf(item.index)))
                .show();
    }

    private void chooseConfigFile() {
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("*/*");
        picker.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{
                "text/plain", "application/json", "application/yaml",
                "application/x-yaml", "text/yaml", "text/x-yaml"
        });
        startActivityForResult(picker, REQUEST_IMPORT_SCRIPT_CONFIG);
    }

    private String readConfigUtf8(Uri uri) throws Exception {
        try (InputStream input = getContentResolver().openInputStream(uri);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            if (input == null) throw new IllegalStateException("无法读取所选配置文件");
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            String decoded = StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(output.toByteArray())).toString();
            return !decoded.isEmpty() && decoded.charAt(0) == 0xFEFF
                    ? decoded.substring(1) : decoded;
        } catch (CharacterCodingException malformed) {
            throw new IllegalArgumentException("配置文件不是有效的 UTF-8 编码", malformed);
        }
    }

    private JSONObject parseScriptConfig(String payload) throws Exception {
        String value = payload == null ? "" : payload.trim();
        if (value.isEmpty()) throw new IllegalArgumentException("配置文件为空");
        if (value.startsWith("{")) {
            JSONObject json = new JSONObject(value);
            if ("FX-SCRIPT-LIST".equals(json.optString("format"))) return json;
            throw new IllegalArgumentException("JSON 文件不是 FX-SCRIPT-LIST 格式");
        }
        String lower = value.toLowerCase(java.util.Locale.ROOT);
        if (lower.contains("scriptings:")) return EgernScriptYamlImporter.parse(value);
        if (lower.contains("script-providers:") && lower.contains("http:")) {
            return StashScriptYamlImporter.parse(value);
        }
        return NativeScriptModuleImporter.parse(value);
    }

    private static int batchCount(String output, String key) {
        if (output == null || key == null) return -1;
        for (String field : output.trim().split("\\s+")) {
            if (!field.startsWith(key + "=")) continue;
            try {
                return Integer.parseInt(field.substring(key.length() + 1));
            } catch (NumberFormatException invalid) {
                return -1;
            }
        }
        return -1;
    }

    private void importScriptConfig(Uri uri) {
        if (busy) return;
        busy = true;
        setControlsEnabled();
        status.setText("正在解析并导入脚本配置…");
        worker.execute(() -> {
            int added = 0;
            int duplicate = 0;
            int failed = 0;
            String failure = null;
            try {
                JSONObject document = parseScriptConfig(readConfigUtf8(uri));
                if (!"FX-SCRIPT-LIST".equals(document.optString("format"))
                        || document.optInt("version", -1) != 1) {
                    throw new IllegalArgumentException("不支持的脚本配置格式或版本");
                }
                org.json.JSONArray entries = document.optJSONArray("scripts");
                if (entries == null || entries.length() == 0) {
                    throw new IllegalArgumentException("没有可导入的脚本条目");
                }

                // Validate the complete document before mutating settings.conf.
                for (int i = 0; i < entries.length(); i++) {
                    org.json.JSONObject entry = entries.optJSONObject(i);
                    if (entry == null || !(entry.opt("value") instanceof String)
                            || !(entry.opt("name") instanceof String)) {
                        throw new IllegalArgumentException("第 " + (i + 1) + " 项字段格式错误");
                    }
                    if (entry.has("enabled") && !(entry.opt("enabled") instanceof Boolean)) {
                        throw new IllegalArgumentException("第 " + (i + 1) + " 项启用状态格式错误");
                    }
                    String scriptValue = entry.getString("value");
                    if (scriptValue.trim().isEmpty()) {
                        throw new IllegalArgumentException("第 " + (i + 1) + " 项内容为空");
                    }
                    if (scriptValue.trim().regionMatches(true, 0, "https://", 0, 8)) {
                        URI parsed;
                        try {
                            parsed = new URI(scriptValue.trim());
                        } catch (URISyntaxException malformed) {
                            throw new IllegalArgumentException("第 " + (i + 1) + " 项 HTTPS 地址格式错误", malformed);
                        }
                        if (!"https".equalsIgnoreCase(parsed.getScheme())
                                || parsed.getHost() == null || parsed.getRawUserInfo() != null
                                || parsed.getPort() == 0 || parsed.getPort() > 65535) {
                            throw new IllegalArgumentException("第 " + (i + 1) + " 项 HTTPS 地址无效");
                        }
                    }
                }

                File manifest = new File(getCacheDir(),
                        "fx-native-script-batch-" + System.nanoTime() + ".list");
                RootAccess.Result result;
                try (FileOutputStream output = new FileOutputStream(manifest, false)) {
                    for (int i = 0; i < entries.length(); i++) {
                        org.json.JSONObject entry = entries.getJSONObject(i);
                        String scriptValue = entry.getString("value");
                        String note = entry.getString("name");
                        String enabled = entry.optBoolean("enabled", true) ? "1" : "0";
                        String trimmed = scriptValue.trim();
                        boolean remote = trimmed.regionMatches(true, 0, "https://", 0, 8);
                        String kind = remote ? "URL" : "SOURCE";
                        String storedValue = remote ? trimmed : scriptValue;
                        String value64 = Base64.encodeToString(
                                storedValue.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
                        String note64 = Base64.encodeToString(
                                note.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
                        String row = kind + "|" + value64 + "|" + note64 + "|" + enabled + "\n";
                        output.write(row.getBytes(StandardCharsets.UTF_8));
                    }
                    output.flush();
                    output.getFD().sync();
                    result = RootAccess.execute(command("add-batch", manifest.getAbsolutePath()),
                            180000L, 32768);
                } finally {
                    manifest.delete();
                }
                if (result.exitCode != 0) {
                    throw new IllegalStateException(message(result));
                }
                added = batchCount(result.output, "added");
                duplicate = batchCount(result.output, "duplicate");
                failed = batchCount(result.output, "failed");
                if (added < 0 || duplicate < 0 || failed < 0) {
                    throw new IllegalStateException("模块没有返回有效的批量导入结果：" + message(result));
                }
                if (added > 0) {
                    RootAccess.Result sync = RootAccess.execute(command("sync"), 180000L, 32768);
                    if (sync.exitCode != 0) {
                        failure = "脚本已保存，但实时订阅同步失败：" + message(sync);
                    }
                }
            } catch (Exception error) {
                failure = error.getClass().getSimpleName() + "："
                        + (error.getMessage() == null ? "脚本配置导入失败" : error.getMessage());
            }

            final int finalAdded = added;
            final int finalDuplicate = duplicate;
            final int finalFailed = failed;
            final String finalFailure = failure;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                busy = false;
                String summary = "配置导入完成：新增 " + finalAdded + " 项，重复跳过 "
                        + finalDuplicate + " 项，失败 " + finalFailed + " 项";
                status.setText(finalFailure == null ? summary : summary + "；" + finalFailure);
                Toast.makeText(this, finalFailure == null ? summary : summary + "；" + finalFailure,
                        Toast.LENGTH_LONG).show();
                setControlsEnabled();
                reload();
            });
        });
    }

    private void chooseLocalScript() {
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("*/*");
        startActivityForResult(picker, REQUEST_IMPORT_SCRIPT);
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_IMPORT_SCRIPT_CONFIG && resultCode == RESULT_OK
                && data != null && data.getData() != null) {
            importScriptConfig(data.getData());
            return;
        }
        if (requestCode == REQUEST_IMPORT_SCRIPT && resultCode == RESULT_OK
                && data != null && data.getData() != null) {
            Uri uri = data.getData();
            String suggested = displayName(uri);
            if (suggested.toLowerCase(java.util.Locale.ROOT).endsWith(".js")) {
                suggested = suggested.substring(0, suggested.length() - 3);
            }
            showImportNameDialog(uri, suggested);
        }
    }

    private String displayName(Uri uri) {
        String value = null;
        try (Cursor cursor = getContentResolver().query(uri,
                new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) value = cursor.getString(0);
        } catch (Exception ignored) { }
        if (value == null || value.trim().isEmpty()) value = uri.getLastPathSegment();
        if (value == null || value.trim().isEmpty()) value = "QuickJS Script";
        return value.trim();
    }

    private void showImportNameDialog(Uri uri, String suggested) {
        EditText name = new EditText(this); name.setTag("fx-form-input");
        name.setSingleLine(true);
        name.setText(suggested);
        name.setHint("脚本名称");
        fxDialogBuilder().setTitle("导入本地 QuickJS 脚本")
                .setMessage("本地源码会保存到 FX 模块脚本清单，不会在导入时执行。")
                .setView(name)
                .setNegativeButton("取消", null)
                .setPositiveButton("导入", (dialog, which) ->
                        importLocalScript(uri, name.getText().toString().trim()))
                .show();
    }

    private void importLocalScript(Uri uri, String name) {
        if (name.isEmpty()) {
            Toast.makeText(this, "脚本名称不能为空", Toast.LENGTH_SHORT).show();
            return;
        }
        if (busy) return;
        busy = true;
        setControlsEnabled();
        status.setText("正在导入本地脚本…");
        worker.execute(() -> {
            File staged = new File(getCacheDir(), "fx-native-script-" + System.nanoTime() + ".js");
            RootAccess.Result result;
            try (InputStream input = getContentResolver().openInputStream(uri);
                 FileOutputStream output = new FileOutputStream(staged, false)) {
                if (input == null) throw new IllegalStateException("无法读取所选文件");
                byte[] buffer = new byte[64 * 1024];
                int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                output.flush();
                output.getFD().sync();
                String note64 = Base64.encodeToString(name.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
                result = RootAccess.execute(command("add-file", staged.getAbsolutePath(), note64, "1"),
                        120000L, 16384);
            } catch (Exception error) {
                result = RootAccess.failure(1, error.getClass().getSimpleName() + ": " + error.getMessage());
            } finally {
                staged.delete();
            }
            final RootAccess.Result completed = result;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                busy = false;
                status.setText(completed.exitCode == 0 ? "本地脚本已导入" : "导入失败：" + message(completed));
                setControlsEnabled();
                if (completed.exitCode != 0) {
                    Toast.makeText(this, "导入失败", Toast.LENGTH_LONG).show();
                }
                reload();
            });
        });
    }

    private void showAddSubscriptionDialog() {
        LinearLayout form = new LinearLayout(this); form.setTag("fx-card");
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(18), dp(4), dp(18), 0);
        EditText url = new EditText(this); url.setTag("fx-form-input");
        url.setSingleLine(true);
        url.setHint("https://example.com/script.js");
        form.addView(url, new LinearLayout.LayoutParams(-1, dp(52)));
        EditText name = new EditText(this); name.setTag("fx-form-input");
        name.setSingleLine(true);
        name.setHint("订阅名称");
        form.addView(name, new LinearLayout.LayoutParams(-1, dp(52)));
        fxDialogBuilder().setTitle("添加 HTTPS 脚本订阅").setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("添加", (dialog, which) -> {
                    String urlValue = url.getText().toString().trim();
                    String noteValue = name.getText().toString().trim();
                    String value64 = Base64.encodeToString(urlValue.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
                    String note64 = Base64.encodeToString(noteValue.getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
                    perform("add-url", value64, note64, "1");
                }).show();
    }

    private void toggleScheduler() {
        perform("scheduler", schedulerRunning ? "stop" : "start");
    }

    private void perform(String action, String... arguments) {
        if (busy) return;
        String[] commandArgs = new String[arguments.length + 1];
        commandArgs[0] = action;
        System.arraycopy(arguments, 0, commandArgs, 1, arguments.length);
        busy = true;
        setControlsEnabled();
        status.setText("正在执行：" + action);
        worker.execute(() -> {
            long timeout = "sync".equals(action) ? 180000L
                    : "run".equals(action) ? 45000L : 120000L;
            RootAccess.Result result = RootAccess.execute(command(commandArgs), timeout, 32768);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                busy = false;
                status.setText(result.exitCode == 0 ? "操作已完成" : "操作失败：" + message(result));
                setControlsEnabled();
                if (result.exitCode != 0) {
                    fxDialogBuilder().setTitle(action.equals("run") ? "脚本执行结果" : "QuickJS 操作失败")
                            .setMessage(message(result)).setPositiveButton("关闭", null).show();
                } else if ("run".equals(action) || "sync".equals(action)) {
                    fxDialogBuilder().setTitle("QuickJS 结果")
                            .setMessage(message(result)).setPositiveButton("关闭", null).show();
                }
                reload();
            });
        });
    }

    private void setControlsEnabled() {
        boolean enabled = !busy;
        if (importLocal != null) importLocal.setEnabled(enabled);
        if (addSubscription != null) addSubscription.setEnabled(enabled);
        if (importConfig != null) importConfig.setEnabled(enabled);
        if (openDiaScripts != null) openDiaScripts.setEnabled(enabled);
        if (syncSubscriptions != null) syncSubscriptions.setEnabled(enabled);
        if (schedulerButton != null) schedulerButton.setEnabled(enabled);
        if (refreshButton != null) refreshButton.setEnabled(enabled);
    }

    private String message(RootAccess.Result result) {
        if (result == null || result.output == null || result.output.trim().isEmpty()) return "模块没有返回信息";
        String value = result.output.trim();
        return value.length() > 3000 ? value.substring(0, 3000) + "…" : value;
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
