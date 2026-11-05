package de.privacyguard.adhook.imported.dia;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONTokener;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/** Native offline JSON editor migrated from Dia 23.11. */
public final class FxDiaJsonActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final int IMPORT_REQUEST = 7411;
    private static final int EXPORT_REQUEST = 7412;
    private static final int MAX_BYTES = 1024 * 1024;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> { Thread t = new Thread(r, "fx-dia-json"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private void submitWorker(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (status != null) status.setText("后台任务队列繁忙，本次操作未执行；请稍后重试。");
                Toast.makeText(this, "后台任务繁忙，请稍后重试。", Toast.LENGTH_LONG).show();
            });
        }
    }
    private EditText source, path;
    private TextView status, result;

    private int dp(float v) { return (int)(v * getResources().getDisplayMetrics().density + 0.5f); }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size); t.setTextColor(color);
        if (bold) t.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        t.setPadding(dp(4), dp(5), dp(4), dp(5)); return t;
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(label); b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(LinearLayout body, String title, String detail, View... children) {
        LinearLayout panel = new LinearLayout(this); panel.setOrientation(1);
        panel.setPadding(dp(14), dp(9), dp(14), dp(9)); panel.setBackgroundColor(0xfff0f3f7);
        panel.addView(text(title, 15, 0xff17212b, true)); panel.addView(text(detail, 12, 0xff617080, false));
        for (View child : children) panel.addView(child);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(4), dp(12), dp(4)); body.addView(panel, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setOrientation(1); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("Hook · JSON 操作", 18, 0xff17212b, true), new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this); body.setOrientation(1); body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body); root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentViewWithNativeTabs(root, 4);

        source = new EditText(this); source.setGravity(Gravity.TOP | Gravity.START);
        source.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        source.setMinLines(12);
        source.setText("{\n  \"name\": \"FX Dia JSON\",\n  \"enabled\": true,\n  \"items\": [1, 2, 3]\n}");
        status = text("离线 JSON 编辑器已就绪。", 12, 0xff526170, false);
        result = text("路径查询结果会显示在这里。", 12, 0xff334155, false);
        card(body, "JSON 数据", "仅在本机处理，不会联网或上传。单个文件上限 1 MiB。",
                source, button("格式化", () -> transform(true)), button("压缩", () -> transform(false)),
                button("校验语法", this::validate), button("复制当前 JSON", () -> copy(source.getText().toString())),
                button("从文件导入", this::pickImport), button("导出 JSON 文件", this::pickExport));
        path = new EditText(this); path.setSingleLine(true); path.setHint("JSON 路径，例如 items[0] 或 user.name");
        card(body, "JSON 路径查询", "支持对象字段和数组下标；查询只读，不修改源数据。",
                path, button("查询路径", this::queryPath));
        card(body, "查询结果", "只显示所选路径的值。", result);
        card(body, "操作状态", "格式化、压缩、校验与文件操作结果。", status);
    }

    private String readSource() {
        String value = source.getText() == null ? "" : source.getText().toString();
        if (value.getBytes(StandardCharsets.UTF_8).length > MAX_BYTES) throw new IllegalArgumentException("JSON 超过 1 MiB 限制。");
        if (value.trim().isEmpty()) throw new IllegalArgumentException("JSON 内容为空。");
        return value;
    }
    private Object parse(String value) throws Exception {
        JSONTokener tokener = new JSONTokener(value);
        Object parsed = tokener.nextValue();
        if (tokener.nextClean() != 0) throw new IllegalArgumentException("JSON 末尾存在多余内容。");
        return parsed;
    }
    private String serialize(Object value, int indent) throws Exception {
        if (value instanceof JSONObject) return ((JSONObject)value).toString(indent);
        if (value instanceof JSONArray) return ((JSONArray)value).toString(indent);
        if (value instanceof String) return JSONObject.quote((String)value);
        return String.valueOf(value);
    }
    private void transform(boolean pretty) {
        final String input;
        try { input = readSource(); } catch (Exception e) { status.setText(e.getMessage()); return; }
        status.setText(pretty ? "正在格式化…" : "正在压缩…");
        submitWorker(() -> {
            try {
                String output = serialize(parse(input), pretty ? 2 : 0);
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) {
                    source.setText(output); status.setText(pretty ? "格式化完成。" : "已压缩 JSON。");
                }});
            } catch (Throwable error) { setError("JSON 处理失败", error); }
        });
    }
    private void validate() {
        final String input;
        try { input = readSource(); } catch (Exception e) { status.setText(e.getMessage()); return; }
        status.setText("正在校验 JSON…");
        submitWorker(() -> {
            try {
                Object parsed = parse(input);
                String type = parsed instanceof JSONObject ? "Object" : parsed instanceof JSONArray ? "Array"
                        : parsed == JSONObject.NULL ? "Null" : parsed.getClass().getSimpleName();
                String message = "JSON 有效 · 根类型：" + type + " · UTF-8 字节：" + input.getBytes(StandardCharsets.UTF_8).length;
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) status.setText(message); });
            } catch (Throwable error) { setError("JSON 校验失败", error); }
        });
    }
    private void queryPath() {
        final String input, expression;
        try {
            input = readSource(); expression = path.getText() == null ? "" : path.getText().toString().trim();
            if (expression.isEmpty()) throw new IllegalArgumentException("请输入 JSON 路径。");
        } catch (Exception e) { result.setText(e.getMessage()); return; }
        submitWorker(() -> {
            try {
                Object current = parse(input); int p = 0;
                while (p < expression.length()) {
                    char c = expression.charAt(p);
                    if (c == '.') { p++; continue; }
                    if (c == '[') {
                        int close = expression.indexOf(']', p + 1);
                        if (close < 0) throw new IllegalArgumentException("数组下标缺少右中括号。");
                        int index;
                        try { index = Integer.parseInt(expression.substring(p + 1, close).trim()); }
                        catch (NumberFormatException e) { throw new IllegalArgumentException("数组下标必须是整数。"); }
                        if (index < 0 || !(current instanceof JSONArray)) throw new IllegalArgumentException("当前值不是数组或下标无效。");
                        current = ((JSONArray)current).get(index); p = close + 1;
                    } else {
                        int end = p;
                        while (end < expression.length() && expression.charAt(end) != '.' && expression.charAt(end) != '[') end++;
                        String key = expression.substring(p, end).trim();
                        if (key.isEmpty() || !(current instanceof JSONObject)) throw new IllegalArgumentException("当前值不是对象或字段为空。");
                        current = ((JSONObject)current).get(key); p = end;
                    }
                }
                String value = serialize(current, 2);
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) {
                    result.setText(value); status.setText("路径查询成功：" + expression);
                }});
            } catch (Throwable error) { setError("路径查询失败", error); }
        });
    }
    private void copy(String value) {
        ClipboardManager manager = (ClipboardManager)getSystemService(CLIPBOARD_SERVICE);
        if (manager != null) {
            manager.setPrimaryClip(ClipData.newPlainText("FX Dia JSON", value));
            Toast.makeText(this, "已复制到剪贴板。", Toast.LENGTH_SHORT).show();
        }
    }
    private void pickImport() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT); intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json");
        try { startActivityForResult(intent, IMPORT_REQUEST); }
        catch (Throwable e) { status.setText("无法打开文件选择器：" + e.getClass().getSimpleName()); }
    }
    private void pickExport() {
        try { readSource(); } catch (Throwable e) { status.setText(e.getMessage()); return; }
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT); intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/json"); intent.putExtra(Intent.EXTRA_TITLE, "dia-json-export.json");
        try { startActivityForResult(intent, EXPORT_REQUEST); }
        catch (Throwable e) { status.setText("无法创建导出文件：" + e.getClass().getSimpleName()); }
    }
    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK || data == null || data.getData() == null) return;
        if (requestCode == IMPORT_REQUEST) importFile(data.getData());
        else if (requestCode == EXPORT_REQUEST) exportFile(data.getData());
    }
    private void importFile(Uri uri) {
        status.setText("正在导入 JSON…");
        submitWorker(() -> {
            try (InputStream input = getContentResolver().openInputStream(uri);
                 ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                if (input == null) throw new IllegalStateException("无法读取所选文件。");
                byte[] buffer = new byte[8192]; int n;
                while ((n = input.read(buffer)) != -1) {
                    if (output.size() > MAX_BYTES - n) throw new IllegalArgumentException("文件超过 1 MiB 限制。");
                    output.write(buffer, 0, n);
                }
                String value = new String(output.toByteArray(), StandardCharsets.UTF_8); parse(value);
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) {
                    source.setText(value); status.setText("JSON 文件已导入并通过语法校验。");
                }});
            } catch (Throwable error) { setError("导入失败", error); }
        });
    }
    private void exportFile(Uri uri) {
        final String value;
        try { value = readSource(); } catch (Throwable error) { status.setText(error.getMessage()); return; }
        submitWorker(() -> {
            try (OutputStream output = getContentResolver().openOutputStream(uri, "w")) {
                if (output == null) throw new IllegalStateException("无法创建导出文件。");
                output.write(value.getBytes(StandardCharsets.UTF_8)); output.flush();
                runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) status.setText("JSON 文件已导出。"); });
            } catch (Throwable error) { setError("导出失败", error); }
        });
    }
    private void setError(String title, Throwable error) {
        String message = error.getMessage() == null ? error.getClass().getSimpleName() : error.getMessage();
        runOnUiThread(() -> { if (!isFinishing() && !isDestroyed()) status.setText(title + "：" + message); });
    }
    @Override protected void onDestroy() { worker.shutdownNow(); super.onDestroy(); }
}
