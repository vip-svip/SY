package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.ClipboardManager;
import android.content.ClipData;
import android.net.Uri;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.io.OutputStream;
import java.io.IOException;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Native viewer and guarded clear operation for the current Dia Frida session log. */
public final class FxDiaSessionLogActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String EXTRA_TARGET_PACKAGE = "fx_dia_session_log_target_package";
    private static final String EXTRA_TARGET_NAME = "fx_dia_session_log_target_name";
    private static final String EXTRA_GADGET_PORT = "fx_dia_session_log_gadget_port";
    private static final int MAX_ROOT_OUTPUT = 512 * 1024;
    private static final int REQUEST_EXPORT_LOG = 7105;
    private static final int MAX_EXPORT_CHARS = 512 * 1024;
    private static final String BASE_DIR = "/data/adb/privacyguard";
    private static final String DIA_DIR = BASE_DIR + "/dia-frida";
    private static final String LOG_DIR = DIA_DIR + "/logs";
    private static final int MAX_RESTORED_SEARCH_CHARS = 256;
    private static final String STATE_SEARCH = "fx_dia_session_log_search";
    private static final String STATE_SCROLL_Y = "fx_dia_session_log_scroll_y";

    // Refresh/clear requests share one bounded worker. A rapid tap burst must
    // not accumulate an unbounded queue of stale Root log reads.
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> {
                Thread thread = new Thread(r, "fx-dia-session-log");
                thread.setDaemon(true);
                return thread;
            },
            new ThreadPoolExecutor.AbortPolicy());
    private String targetPackage;
    private boolean gadgetLog;
    private String targetName;
    private String logPath;
    private String logContent = "";
    private int requestGeneration;
    private boolean destroyed;

    private TextView status;
    private TextView outputView;
    private EditText search;
    private ScrollView logScroll;
    private boolean logLoaded;
    private boolean pendingScrollRestore;
    private int restoredScrollY;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT,
                android.graphics.Typeface.BOLD);
        view.setPadding(dp(5), dp(6), dp(5), dp(6));
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

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        targetPackage = getIntent().getStringExtra(EXTRA_TARGET_PACKAGE);
        targetName = getIntent().getStringExtra(EXTRA_TARGET_NAME);
        int gadgetPort = getIntent().getIntExtra(EXTRA_GADGET_PORT, -1);
        if (gadgetPort >= 1024 && gadgetPort <= 65535 && gadgetPort != 27042) {
            gadgetLog = true;
            logPath = LOG_DIR + "/gadget-" + gadgetPort + ".log";
            targetName = "Gadget Listen · 127.0.0.1:" + gadgetPort;
        } else {
            if (!isSafePackageName(targetPackage)) {
                Toast.makeText(this, "运行日志目标包名无效，无法读取日志。", Toast.LENGTH_LONG).show();
                finish();
                return;
            }
            if (targetName == null || targetName.trim().isEmpty()) targetName = targetPackage;
            logPath = LOG_DIR + "/" + targetPackage + ".log";
        }
        buildPage();
        restoreUiState(state);
        refreshLog();
    }

    private static boolean isSafePackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+")
                && !value.contains("..");
    }

    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private String checkedDirectoryPrefix() {
        return "if [ -L '/data' ] || [ ! -d '/data' ]"
                + " || [ -L '/data/adb' ] || [ ! -d '/data/adb' ]"
                + " || [ -L " + quote(BASE_DIR) + " ] || [ ! -d " + quote(BASE_DIR) + " ]"
                + " || [ -L " + quote(DIA_DIR) + " ] || [ ! -d " + quote(DIA_DIR) + " ]"
                + " || [ -L " + quote(LOG_DIR) + " ] || [ ! -d " + quote(LOG_DIR) + " ]; then "
                + "echo FX_DIA_LOG_PATH_UNAVAILABLE; exit 21; fi; ";
    }

    private void buildPage() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(8), dp(4), dp(12), dp(4));
        header.addView(button("‹ 返回 Hook", this::finish));
        TextView pageTitle = text(gadgetLog ? "Hook · Gadget 消息/控制台" : "Hook · Frida 运行日志", 18, 0xff17212b, true);
        pageTitle.setTag("fx-title:18");
        header.addView(pageTitle, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        TextView targetIdentity = text(gadgetLog ? targetName : "目标应用：" + targetName + "\n包名：" + targetPackage,
                12, 0xff526170, false);
        targetIdentity.setTag("fx-card-detail");
        root.addView(targetIdentity);

        TextView warning = text(
                gadgetLog
                        ? "这里显示指定 Gadget Listen 端口的消息/console 输出，可能包含脚本输出或调试信息。分享前请检查并删除敏感内容。"
                        : "这里显示当前目标的原始 Frida 会话日志，可能包含自定义脚本输出或应用调试信息。分享前请检查并删除敏感内容。",
                12, 0xff8a5b20, false);
        warning.setPadding(dp(16), dp(4), dp(16), dp(4));
        root.addView(warning);

        status = text("尚未读取日志。", 12, 0xff526170, false);
        status.setTag("fx-card-detail");
        status.setPadding(dp(16), dp(5), dp(16), dp(5));
        root.addView(status);

        LinearLayout controls = new LinearLayout(this);
        controls.setTag("fx-card-group");
        controls.setOrientation(LinearLayout.VERTICAL);
        controls.setPadding(dp(10), dp(2), dp(10), dp(4));
        search = new EditText(this);
        search.setSingleLine(true);
        search.setHint("筛选日志行");
        controls.addView(search);
        LinearLayout actions = new LinearLayout(this);
        actions.setTag("fx-card-group");
        actions.addView(button("刷新日志", this::refreshLog),
                new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("复制筛选结果", this::copyFilteredLog),
                new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("导出筛选结果", this::beginExportLog),
                new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("清空当前日志", this::confirmClearLog),
                new LinearLayout.LayoutParams(0, -2, 1));
        controls.addView(actions);
        LinearLayout secondaryActions = new LinearLayout(this);
        secondaryActions.setTag("fx-card-group");
        secondaryActions.addView(button("分享筛选结果", this::shareFilteredLog),
                new LinearLayout.LayoutParams(0, -2, 1));
        controls.addView(secondaryActions);
        root.addView(controls);

        logScroll = new ScrollView(this);
        logScroll.setFillViewport(true);
        outputView = text("正在读取…", 11, 0xff263443, false);
        outputView.setTypeface(android.graphics.Typeface.MONOSPACE);
        outputView.setTextIsSelectable(true);
        outputView.setPadding(dp(12), dp(8), dp(12), dp(18));
        logScroll.addView(outputView);
        root.addView(logScroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 4);

        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count,
                                                    int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before,
                                                int count) { renderLog(); }
            @Override public void afterTextChanged(Editable editable) { }
        });
    }

    private void refreshLog() {
        if (destroyed || logPath == null) return;
        final int request = ++requestGeneration;
        status.setText("正在读取最近 500 行日志…");
        final String command = checkedDirectoryPrefix()
                + "if [ -f " + quote(logPath) + " ] && [ ! -L " + quote(logPath)
                + " ] && [ -r " + quote(logPath) + " ] && [ -s " + quote(logPath)
                + " ]; then tail -n 500 " + quote(logPath)
                + "; else echo FX_DIA_NO_LOG; fi";
        submit(() -> {
            RootAccess.Result result = RootAccess.execute(command, 15000L, MAX_ROOT_OUTPUT);
            runOnUiThread(() -> {
                if (destroyed || isFinishing() || isDestroyed()
                        || request != requestGeneration) return;
                if (result == null || result.exitCode != 0) {
                    String detail = result == null || result.output == null
                            ? "Root 读取失败。" : result.output.trim();
                    if (detail.length() > 240) detail = detail.substring(0, 240);
                    logContent = "";
                    status.setText("读取日志失败：" + (detail.isEmpty() ? "没有错误详情。" : detail));
                    logLoaded = true;
                    renderLog();
                    return;
                }
                String value = result.output == null ? "" : result.output;
                if (value.contains("FX_DIA_LOG_PATH_UNAVAILABLE")) {
                    logContent = "";
                    status.setText("日志目录不存在、不可访问或包含符号链接；为保护路径安全，拒绝读取。");
                } else if (value.contains("FX_DIA_NO_LOG")) {
                    logContent = "";
                    status.setText("当前目标还没有会话日志。");
                } else {
                    logContent = value;
                    int lines = value.isEmpty() ? 0 : value.split("\\r?\\n", -1).length;
                    String time = new SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(new Date());
                    status.setText("最近读取：" + time + " · 返回 " + lines + " 行（最多 500 行）。");
                }
                logLoaded = true;
                renderLog();
            });
        });
    }

    private String getFilteredLogContent() {
        String needle = search == null || search.getText() == null ? ""
                : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        if (logContent.isEmpty()) return "";
        StringBuilder filtered = new StringBuilder();
        for (String line : logContent.split("\\r?\\n", -1)) {
            if (!needle.isEmpty() && !line.toLowerCase(Locale.ROOT).contains(needle)) continue;
            if (filtered.length() > 0) filtered.append('\n');
            filtered.append(line);
        }
        return filtered.toString();
    }

    private void renderLog() {
        if (outputView == null || search == null) return;
        if (logContent.isEmpty()) {
            outputView.setText("暂无可显示的运行日志。");
            restorePendingScrollPosition();
            return;
        }
        String filtered = getFilteredLogContent();
        outputView.setText(filtered.isEmpty() ? "没有符合条件的日志行。" : filtered);
        restorePendingScrollPosition();
    }

    private void copyFilteredLog() {
        String filtered = getFilteredLogContent();
        if (filtered.isEmpty()) {
            Toast.makeText(this, "当前没有可复制的日志内容。", Toast.LENGTH_SHORT).show();
            return;
        }
        ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (clipboard == null) {
            Toast.makeText(this, "系统剪贴板不可用，未复制日志。", Toast.LENGTH_LONG).show();
            return;
        }
        clipboard.setPrimaryClip(ClipData.newPlainText(
                gadgetLog ? "FX Gadget 日志" : "FX Frida 会话日志", filtered));
        Toast.makeText(this, "已复制当前筛选结果（" + filtered.length() + " 字符）。",
                Toast.LENGTH_SHORT).show();
    }

    private void shareFilteredLog() {
        String filtered = getFilteredLogContent();
        if (filtered.isEmpty()) {
            Toast.makeText(this, "当前没有可分享的日志内容。", Toast.LENGTH_SHORT).show();
            return;
        }
        final int shareLimit = 48 * 1024;
        String header = "FX Dia 会话日志 · " + targetName + " · "
                + (gadgetLog ? "Gadget" : "Frida") + "\\n"
                + "包名：" + targetPackage + "\\n"
                + "导出时间：" + new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
                        .format(new Date()) + "\\n"
                + "注意：分享前请检查日志中的敏感信息。\\n\\n";
        String payload = header + filtered;
        if (utf8Length(payload) > shareLimit) {
            String marker = "\\n[分享内容达到 48 KiB 上限，后续日志已省略]";
            payload = truncateUtf8(payload, shareLimit - utf8Length(marker)) + marker;
        }
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_SUBJECT, "FX Dia 会话日志 · " + targetName);
        send.putExtra(Intent.EXTRA_TEXT, payload);
        try {
            startActivity(Intent.createChooser(send, "分享筛选后的 Dia 日志"));
        } catch (RuntimeException unavailable) {
            Toast.makeText(this, "系统分享面板不可用，未分享日志。", Toast.LENGTH_LONG).show();
        }
    }
    private void beginExportLog() {
        String filtered = getFilteredLogContent();
        if (filtered.isEmpty()) {
            Toast.makeText(this, "当前筛选没有可导出的日志。", Toast.LENGTH_SHORT).show();
            return;
        }
        Intent create = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        create.addCategory(Intent.CATEGORY_OPENABLE);
        create.setType("text/plain");
        create.putExtra(Intent.EXTRA_TITLE,
                (gadgetLog ? "FX-Gadget-" : "FX-Frida-") + targetPackage + ".log.txt");
        try {
            startActivityForResult(create, REQUEST_EXPORT_LOG);
        } catch (RuntimeException unavailable) {
            Toast.makeText(this, "系统文件创建器不可用，未导出日志。", Toast.LENGTH_LONG).show();
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_EXPORT_LOG || resultCode != RESULT_OK
                || data == null || data.getData() == null) return;
        String filtered = getFilteredLogContent();
        if (filtered.isEmpty()) {
            Toast.makeText(this, "筛选结果已变化，没有可导出的日志。", Toast.LENGTH_SHORT).show();
            return;
        }
        String header = "FX Dia 会话日志导出\\n"
                + "目标：" + targetName + "\\n"
                + "包名：" + targetPackage + "\\n"
                + "日志类型：" + (gadgetLog ? "Gadget" : "Frida") + "\\n"
                + "导出时间：" + new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT)
                        .format(new Date()) + "\\n"
                + "说明：日志可能包含脚本或目标应用输出的敏感信息，请妥善保管。\\n\\n";
        String content = header + filtered;
        boolean truncated = utf8Length(content) > MAX_EXPORT_CHARS;
        if (truncated) {
            String marker = "\\n[导出达到 512 KiB 上限，后续内容已省略]\\n";
            content = truncateUtf8(content, MAX_EXPORT_CHARS - utf8Length(marker)) + marker;
        }
        try (OutputStream stream = getContentResolver().openOutputStream(data.getData(), "w")) {
            if (stream == null) throw new IOException("无法打开目标文件");
            byte[] bytes = content.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            stream.write(bytes);
            stream.flush();
            Toast.makeText(this, "已导出筛选日志（" + bytes.length + " 字节）。",
                    Toast.LENGTH_LONG).show();
        } catch (IOException | SecurityException failure) {
            Toast.makeText(this, "导出失败，未能写入目标文件："
                    + failure.getClass().getSimpleName(), Toast.LENGTH_LONG).show();
        }
    }

    private static int utf8Length(String value) {
        if (value == null || value.isEmpty()) return 0;
        int bytes = 0;
        for (int i = 0; i < value.length();) {
            int codePoint = value.codePointAt(i);
            bytes += codePoint <= 0x7f ? 1 : codePoint <= 0x7ff ? 2
                    : codePoint <= 0xffff ? 3 : 4;
            i += Character.charCount(codePoint);
        }
        return bytes;
    }

    private static String truncateUtf8(String value, int maxBytes) {
        if (value == null || maxBytes <= 0) return "";
        StringBuilder bounded = new StringBuilder();
        int bytes = 0;
        for (int i = 0; i < value.length();) {
            int codePoint = value.codePointAt(i);
            int size = codePoint <= 0x7f ? 1 : codePoint <= 0x7ff ? 2
                    : codePoint <= 0xffff ? 3 : 4;
            if (bytes + size > maxBytes) break;
            bounded.appendCodePoint(codePoint);
            bytes += size;
            i += Character.charCount(codePoint);
        }
        return bounded.toString();
    }

    private void restoreUiState(Bundle state) {
        if (state == null) return;
        String query = state.getString(STATE_SEARCH, "");
        if (query == null) query = "";
        if (query.length() > MAX_RESTORED_SEARCH_CHARS) {
            query = query.substring(0, MAX_RESTORED_SEARCH_CHARS);
        }
        search.setText(query);
        search.setSelection(search.getText().length());
        restoredScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
        pendingScrollRestore = true;
    }

    private void restorePendingScrollPosition() {
        if (!logLoaded || !pendingScrollRestore || logScroll == null) return;
        final int scrollY = restoredScrollY;
        pendingScrollRestore = false;
        logScroll.post(() -> {
            if (!destroyed && logScroll != null) logScroll.scrollTo(0, scrollY);
        });
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (search != null) {
            String query = search.getText() == null ? "" : search.getText().toString();
            if (query.length() > MAX_RESTORED_SEARCH_CHARS) {
                query = query.substring(0, MAX_RESTORED_SEARCH_CHARS);
            }
            outState.putString(STATE_SEARCH, query);
        }
        if (logScroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, logScroll.getScrollY()));
    }

    private void confirmClearLog() {
        fxDialogBuilder()
                .setTitle("清空 Frida 会话日志")
                .setMessage("只清空 FX 为当前目标创建的会话日志，不会删除脚本、目标应用配置或 Frida 服务。此操作不可撤销。")
                .setNegativeButton("取消", null)
                .setPositiveButton("清空日志", (dialog, which) -> clearLog())
                .show();
    }

    private void clearLog() {
        final int request = ++requestGeneration;
        status.setText("正在安全清空当前目标日志…");
        final String command = checkedDirectoryPrefix()
                + "if [ -f " + quote(logPath) + " ] && [ ! -L " + quote(logPath)
                + " ]; then : > " + quote(logPath) + " && chmod 600 " + quote(logPath)
                + " && echo FX_DIA_LOG_CLEARED; else echo FX_DIA_LOG_MISSING_OR_UNSAFE; exit 22; fi";
        submit(() -> {
            RootAccess.Result result = RootAccess.execute(command, 15000L, 64 * 1024);
            runOnUiThread(() -> {
                if (destroyed || isFinishing() || isDestroyed()
                        || request != requestGeneration) return;
                if (result != null && result.exitCode == 0
                        && result.output != null && result.output.contains("FX_DIA_LOG_CLEARED")) {
                    logContent = "";
                    if (search != null) search.setText("");
                    status.setText(gadgetLog ? "当前 Gadget 端口的 FX 日志已清空。" : "当前目标的 FX Frida 日志已清空。");
                    renderLog();
                    Toast.makeText(this, "日志已清空。", Toast.LENGTH_SHORT).show();
                } else {
                    String detail = result == null || result.output == null
                            ? "Root 操作失败。" : result.output.trim();
                    if (detail.length() > 240) detail = detail.substring(0, 240);
                    status.setText("清空失败，日志未被确认清空：" + detail);
                }
            });
        });
    }

    private void submit(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            status.setText("后台队列繁忙，本次操作未执行，请稍后重试。");
            logLoaded = true;
            renderLog();
        }
    }

    @Override protected void onDestroy() {
        destroyed = true;
        requestGeneration++;
        worker.shutdownNow();
        super.onDestroy();
    }
}
