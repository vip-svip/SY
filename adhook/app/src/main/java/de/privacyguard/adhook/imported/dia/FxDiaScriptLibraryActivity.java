package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import android.text.Editable;
import android.text.TextWatcher;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Dedicated native Dia fourth-level page for the shared Frida JavaScript library. */
public final class FxDiaScriptLibraryActivity extends Activity {
    private static final int REQUEST_EDITOR = 0x3a11;
    private static final int REQUEST_IMPORT = 0x3a12;
    private static final int REQUEST_EXPORT = 0x3a13;
    private static final String STATE_EDITING_NAME = "fx_dia_script_library_editing_name";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(4),
            r -> { Thread t = new Thread(r, "fx-dia-script-library"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private LinearLayout rows;
    private EditText search;
    private TextView status;
    private JSONObject scripts = new JSONObject();
    private String editingName;
    private boolean openingInitialEditor;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private void card(LinearLayout parent, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(12), dp(8), dp(12), dp(8));
        panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 15, 0xff17212b, true));
        panel.addView(text(detail, 11, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(10), dp(4), dp(10), dp(4));
        parent.addView(panel, lp);
    }

    private void submitIo(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            setStatus("后台任务队列繁忙，本次操作未执行；请稍后重试。");
        }
    }

    private void setStatus(String value) {
        if (status != null && !isFinishing() && !isDestroyed()) status.setText(value);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) editingName = state.getString(STATE_EDITING_NAME);
        openingInitialEditor = getIntent() != null
                && getIntent().getBooleanExtra("open_new_script", false);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(5), dp(12), dp(5));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Dia 23.11 · Frida JavaScript 脚本库", 17, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(16));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);

        status = text("正在读取本机 Frida 脚本库…", 12, 0xff617080, false);
        card(body, "本地脚本库", "数据与 Dia Frida 管理页共用同一私有配置和 JSON schema；载入、编辑、删除和导入不会自动执行脚本。",
                status);
        search = new EditText(this);
        search.setSingleLine(true);
        search.setHint("搜索脚本名称");
        body.addView(search, new LinearLayout.LayoutParams(-1, -2));
        LinearLayout actions = new LinearLayout(this);
        actions.setOrientation(LinearLayout.HORIZONTAL);
        actions.addView(button("新建脚本", this::createScript), new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("导入 JSON", this::chooseImport), new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("导出 JSON", this::chooseExport), new LinearLayout.LayoutParams(0, -2, 1));
        body.addView(actions);
        rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        body.addView(rows, new LinearLayout.LayoutParams(-1, -2));

        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                renderRows();
            }
            @Override public void afterTextChanged(Editable editable) { }
        });
        reload();
    }

    private void reload() {
        setStatus("正在读取本机 Frida 脚本库…");
        submitIo(() -> {
            final JSONObject loaded;
            try {
                loaded = FxDiaScriptLibraryStore.read(this);
            } catch (Throwable error) {
                runOnUiThread(() -> setStatus("读取脚本库失败：" + detail(error)));
                return;
            }
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                scripts = loaded;
                renderRows();
                setStatus("已读取 " + scripts.length() + " 个本地脚本。数据保存在 FX 私有应用配置中。");
                if (openingInitialEditor) {
                    openingInitialEditor = false;
                    createScript();
                }
            });
        });
    }

    private void renderRows() {
        if (rows == null) return;
        rows.removeAllViews();
        String query = search == null || search.getText() == null
                ? "" : search.getText().toString().trim().toLowerCase(java.util.Locale.ROOT);
        List<String> names = new ArrayList<>();
        Iterator<String> iterator = scripts.keys();
        while (iterator.hasNext()) {
            String name = iterator.next();
            if (query.isEmpty() || name.toLowerCase(java.util.Locale.ROOT).contains(query)) {
                names.add(name);
            }
        }
        Collections.sort(names, String.CASE_INSENSITIVE_ORDER);
        if (names.isEmpty()) {
            rows.addView(text(query.isEmpty()
                    ? "脚本库为空。可新建脚本，或导入兼容的 FX-DIA-FRIDA-SCRIPTS-1 JSON。"
                    : "没有匹配的脚本名称。", 13, 0xff617080, false));
            return;
        }
        for (String name : names) {
            String source = scripts.optString(name, "");
            int bytes = source.getBytes(StandardCharsets.UTF_8).length;
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.VERTICAL);
            row.setPadding(dp(12), dp(7), dp(12), dp(7));
            row.setBackgroundColor(0xfff0f3f7);
            row.addView(text(name, 14, 0xff17212b, true));
            row.addView(text("UTF-8 " + bytes + " bytes · 不会自动执行", 11, 0xff617080, false));
            LinearLayout buttons = new LinearLayout(this);
            buttons.setOrientation(LinearLayout.HORIZONTAL);
            buttons.addView(button("编辑", () -> openEditor(name, source)),
                    new LinearLayout.LayoutParams(0, -2, 1));
            buttons.addView(button("删除", () -> confirmDelete(name)),
                    new LinearLayout.LayoutParams(0, -2, 1));
            row.addView(buttons);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(10), dp(3), dp(10), dp(3));
            rows.addView(row, lp);
        }
    }

    private void createScript() {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint("脚本名称，最多 64 个字符");
        new AlertDialog.Builder(this).setTitle("新建 Frida JavaScript")
                .setMessage("新脚本会先打开本地编辑器。保存回传后才写入私有脚本库，不会自动注入目标进程。")
                .setView(input)
                .setNegativeButton("取消", null)
                .setPositiveButton("继续", (dialog, which) -> {
                    String name = FxDiaScriptLibraryPolicy.normalizeName(
                            input.getText() == null ? "" : input.getText().toString());
                    String error = FxDiaScriptLibraryPolicy.validateName(name);
                    if (error != null) {
                        setStatus(error);
                        return;
                    }
                    if (!scripts.has(name)) {
                        error = FxDiaScriptLibraryPolicy.validateCount(scripts.length(), false);
                        if (error != null) {
                            setStatus(error);
                            return;
                        }
                        openEditor(name, "");
                        return;
                    }
                    new AlertDialog.Builder(this).setTitle("脚本名称已存在")
                            .setMessage("“" + name + "”已存在。继续编辑会在保存时覆盖该脚本。")
                            .setNegativeButton("取消", null)
                            .setPositiveButton("编辑现有脚本", (d, w) ->
                                    openEditor(name, scripts.optString(name, ""))).show();
                }).show();
    }

    private void openEditor(String name, String source) {
        editingName = name;
        Intent intent = new Intent(this, FxDiaCodeEditorActivity.class);
        intent.putExtra(FxDiaCodeEditorActivity.EXTRA_CODE, source);
        intent.putExtra(FxDiaCodeEditorActivity.EXTRA_LANGUAGE, "javascript");
        try {
            startActivityForResult(intent, REQUEST_EDITOR);
        } catch (RuntimeException error) {
            setStatus("无法打开 JavaScript 编辑器：" + detail(error));
        }
    }

    private void confirmDelete(String name) {
        new AlertDialog.Builder(this).setTitle("删除脚本？")
                .setMessage("确认从 FX 本地 Frida 脚本库删除“" + name + "”？此操作不会影响已导出的 JSON 文件。")
                .setNegativeButton("取消", null)
                .setPositiveButton("删除", (dialog, which) -> submitIo(() -> {
                    try {
                        FxDiaScriptLibraryStore.delete(this, name);
                        JSONObject loaded = FxDiaScriptLibraryStore.read(this);
                        runOnUiThread(() -> {
                            if (isFinishing() || isDestroyed()) return;
                            scripts = loaded;
                            renderRows();
                            setStatus("已删除脚本：" + name);
                        });
                    } catch (Throwable error) {
                        runOnUiThread(() -> setStatus("删除失败：" + detail(error)));
                    }
                })).show();
    }

    private void chooseImport() {
        Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        pick.addCategory(Intent.CATEGORY_OPENABLE);
        pick.setType("application/json");
        try {
            startActivityForResult(pick, REQUEST_IMPORT);
        } catch (RuntimeException error) {
            setStatus("无法打开 JSON 文件选择器：" + detail(error));
        }
    }

    private void chooseExport() {
        Intent create = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        create.addCategory(Intent.CATEGORY_OPENABLE);
        create.setType("application/json");
        create.putExtra(Intent.EXTRA_TITLE, "FX-Dia-Frida-Scripts.json");
        try {
            startActivityForResult(create, REQUEST_EXPORT);
        } catch (RuntimeException error) {
            setStatus("无法打开 JSON 保存选择器：" + detail(error));
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        // The code editor returns its source in an Intent extra and uses Dia's
        // custom result code. It does not return a SAF Uri; handle it first.
        if (requestCode == REQUEST_EDITOR) {
            if (resultCode != FxDiaCodeEditorActivity.RESULT_CODE_EDITOR || data == null) {
                editingName = null;
                setStatus("编辑器未保存，脚本库保持不变。");
                return;
            }
            final String name = editingName;
            editingName = null;
            final String source = data.getStringExtra(FxDiaCodeEditorActivity.EXTRA_CODE);
            if (name == null || name.trim().isEmpty()) {
                setStatus("编辑器返回时没有有效的脚本名称，未保存。");
                return;
            }
            String validation = FxDiaScriptLibraryPolicy.validateSource(source);
            if (validation != null) {
                setStatus(validation + " 脚本库保持不变。");
                return;
            }
            submitIo(() -> {
                try {
                    FxDiaScriptLibraryStore.save(this, name, source);
                    JSONObject loaded = FxDiaScriptLibraryStore.read(this);
                    runOnUiThread(() -> {
                        if (isFinishing() || isDestroyed()) return;
                        scripts = loaded;
                        renderRows();
                        setStatus("已保存脚本：“" + name + "”。尚未执行或注入。");
                    });
                } catch (Throwable error) {
                    runOnUiThread(() -> setStatus("保存脚本失败：" + detail(error)));
                }
            });
            return;
        }

        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            if (requestCode == REQUEST_IMPORT) setStatus("已取消脚本库导入。");
            else if (requestCode == REQUEST_EXPORT) setStatus("已取消脚本库导出。");
            return;
        }
        Uri uri = data.getData();
        if (requestCode == REQUEST_IMPORT) importFrom(uri);
        else if (requestCode == REQUEST_EXPORT) exportTo(uri);
    }

    private void importFrom(Uri uri) {
        setStatus("正在读取脚本库 JSON…");
        submitIo(() -> {
            final String json;
            final FxDiaScriptLibraryStore.ImportPreview preview;
            try (InputStream input = getContentResolver().openInputStream(uri);
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取所选 JSON 文件。");
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() > FxDiaScriptLibraryPolicy.MAX_LIBRARY_JSON_BYTES - count) {
                        throw new IllegalArgumentException("脚本库 JSON 超过 1 MiB。");
                    }
                    output.write(buffer, 0, count);
                }
                json = new String(output.toByteArray(), StandardCharsets.UTF_8);
                preview = FxDiaScriptLibraryStore.previewImport(this, json);
            } catch (Throwable error) {
                runOnUiThread(() -> setStatus("脚本库导入校验失败：" + detail(error)));
                return;
            }
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                String message = "将导入 " + preview.count + " 个脚本。";
                if (!preview.overwrittenNames.isEmpty()) {
                    message += "\n同名脚本将被覆盖（" + preview.overwrittenNames.size() + " 个）："
                            + String.join("、", preview.overwrittenNames.subList(
                                    0, Math.min(5, preview.overwrittenNames.size())));
                    if (preview.overwrittenNames.size() > 5) message += " 等";
                }
                new AlertDialog.Builder(this).setTitle("确认导入脚本库")
                        .setMessage(message + "\n不会自动执行导入的脚本。")
                        .setNegativeButton("取消", null)
                        .setPositiveButton("验证并导入", (dialog, which) -> submitIo(() -> {
                            try {
                                int count = FxDiaScriptLibraryStore.mergeImport(this, json);
                                JSONObject loaded = FxDiaScriptLibraryStore.read(this);
                                runOnUiThread(() -> {
                                    if (isFinishing() || isDestroyed()) return;
                                    scripts = loaded;
                                    renderRows();
                                    setStatus("已导入 " + count + " 个脚本。导入内容未执行。");
                                });
                            } catch (Throwable error) {
                                runOnUiThread(() -> setStatus("导入失败：" + detail(error)));
                            }
                        })).show();
            });
        });
    }

    private void exportTo(Uri uri) {
        setStatus("正在导出脚本库 JSON…");
        submitIo(() -> {
            String message;
            try {
                String json = FxDiaScriptLibraryStore.exportJson(this);
                try (OutputStream output = getContentResolver().openOutputStream(uri, "w")) {
                    if (output == null) throw new IllegalStateException("无法写入所选 JSON 文件。");
                    byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
                    if (bytes.length > FxDiaScriptLibraryPolicy.MAX_LIBRARY_JSON_BYTES) {
                        throw new IllegalArgumentException("脚本库 JSON 超过 1 MiB。");
                    }
                    output.write(bytes);
                    output.flush();
                }
                message = "脚本库 JSON 已导出。";
            } catch (Throwable error) {
                message = "导出失败：" + detail(error);
            }
            String result = message;
            runOnUiThread(() -> setStatus(result));
        });
    }

    private String detail(Throwable error) {
        if (error == null) return "未知错误";
        String value = error.getClass().getSimpleName()
                + (error.getMessage() == null ? "" : "： " + error.getMessage());
        return value.length() > 400 ? value.substring(0, 400) + "…" : value;
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        if (editingName != null) out.putString(STATE_EDITING_NAME, editingName);
        super.onSaveInstanceState(out);
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
