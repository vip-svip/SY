package de.privacyguard.adhook;

import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Dedicated native viewer for the selected application's FX Hook OBSERVE records.
 * It reads only bounded logcat entries matching the FX-owned observer tag and
 * exact target package; no user-provided text is ever interpolated into shell.
 */
public final class FxHookObservationLogsActivity extends FxNativeTabActivity {
    public static final String EXTRA_TARGET_PACKAGE = "fx_hook_observation_target_package";
    public static final String EXTRA_TARGET_LABEL = "fx_hook_observation_target_label";
    private static final int ROOT_OUTPUT_LIMIT = 64 * 1024;
    private static final int DISPLAY_LIMIT = 24 * 1024;

    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "fx-hook-observation-log");
        thread.setDaemon(true);
        return thread;
    });

    private String targetPackage;
    private String targetLabel;
    private String rawOutput = "";
    private int generation;
    private boolean destroyed;
    private final AtomicBoolean refreshInFlight = new AtomicBoolean(false);
    private Button refreshButton;

    private TextView status;
    private TextView count;
    private TextView outputView;
    private EditText search;
    private ScrollView logScroll;
    private String restoredSearch = "";
    private int restoredScrollY;
    private boolean restoreScrollPending;

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
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        targetPackage = getIntent().getStringExtra(EXTRA_TARGET_PACKAGE);
        targetLabel = getIntent().getStringExtra(EXTRA_TARGET_LABEL);
        if (state != null) {
            restoredSearch = state.getString("fx_hook_observe_search", "");
            restoredScrollY = Math.max(0, state.getInt("fx_hook_observe_scroll_y", 0));
            restoreScrollPending = true;
        }
        if (!isSafePackageName(targetPackage)) {
            Toast.makeText(this, "OBSERVE 日志目标包名无效，无法读取。", Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        if (targetLabel == null || targetLabel.trim().isEmpty()) targetLabel = targetPackage;
        buildPage();
        refresh();
    }

    private static boolean isSafePackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                && !value.contains("..");
    }

    private String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private String observationCommand() {
        // Keep parity with MainActivity's nativeModuleCommand path resolver.
        String prefix = "MP=; for d in /data/adb/modules/privacyguard "
                + "/data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard "
                + "/data/adb/modules/pg; do "
                + "[ -f \"$d/module.prop\" ] && { MP=\"$d\"; break; }; done; "
                + "[ -n \"$MP\" ] || { echo FX_HOOK_MODULE_UNAVAILABLE; exit 20; }; ";
        String filter = shellQuote("package=" + targetPackage + " executable=");
        return prefix
                + "command -v logcat >/dev/null 2>&1 || { echo LOGCAT_UNAVAILABLE; exit 22; }; "
                + "logcat -d -v threadtime -t 5000 2>/dev/null "
                + "| grep -F 'FX Hook' | grep -E 'dev-observe|dia-dialog-match' | grep -F "
                + filter + " | tail -n 300 || true";
    }

    private void buildPage() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(8), dp(4), dp(12), dp(4));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("FX Hook · OBSERVE / Dialog 匹配日志", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        TextView target = text("目标应用：" + targetLabel + "\n包名：" + targetPackage,
                12, 0xff526170, false);
        target.setPadding(dp(16), dp(3), dp(16), dp(7));
        root.addView(target);

        TextView privacy = text(
                "只读取 FX Hook 标记的 dev-observe 与 dia-dialog-match 记录，并按目标包名精确筛选。Dialog 记录仅包含匹配类型，不保存弹窗全文；方法观察记录不读取参数或返回值。请勿将日志当作目标进程当前仍在运行的证明。",
                12, 0xff617080, false);
        privacy.setPadding(dp(16), dp(4), dp(16), dp(4));
        root.addView(privacy);

        status = text("正在读取 OBSERVE / Dialog 匹配记录…", 12, 0xff526170, false);
        status.setPadding(dp(16), dp(5), dp(16), dp(5));
        root.addView(status);

        LinearLayout controls = new LinearLayout(this);
        controls.setOrientation(LinearLayout.VERTICAL);
        controls.setPadding(dp(10), dp(2), dp(10), dp(4));
        search = new EditText(this);
        search.setSingleLine(true);
        search.setHint("搜索类名、方法或 Dialog 匹配类型");
        controls.addView(search);

        LinearLayout actions = new LinearLayout(this);
        refreshButton = button("刷新日志", this::refresh);
        actions.addView(refreshButton, new LinearLayout.LayoutParams(0, -2, 1));
        actions.addView(button("清除筛选", () -> search.setText("")),
                new LinearLayout.LayoutParams(0, -2, 1));
        controls.addView(actions);
        root.addView(controls);

        count = text("匹配记录：0", 12, 0xff617080, false);
        count.setPadding(dp(16), dp(4), dp(16), dp(4));
        root.addView(count);

        search.setText(restoredSearch);
        ScrollView scroll = new ScrollView(this);
        logScroll = scroll;
        scroll.setFillViewport(true);
        outputView = text("正在读取…", 11, 0xff263443, false);
        outputView.setTypeface(android.graphics.Typeface.MONOSPACE);
        outputView.setTextIsSelectable(true);
        outputView.setPadding(dp(12), dp(8), dp(12), dp(18));
        scroll.addView(outputView);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 4);
        scroll.post(() -> scroll.scrollTo(0, restoredScrollY));

        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count,
                                                    int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before,
                                                int count) {
                render();
            }
            @Override public void afterTextChanged(Editable editable) { }
        });
    }

    private void refresh() {
        if (destroyed || targetPackage == null) return;
        if (!refreshInFlight.compareAndSet(false, true)) {
            if (status != null) status.setText("日志读取正在进行，请等待当前请求完成。");
            return;
        }
        final int request = ++generation;
        if (refreshButton != null) refreshButton.setEnabled(false);
        status.setText("正在读取最近 5000 条系统日志中的 FX Hook OBSERVE 记录…");
        try {
            worker.execute(() -> {
                RootAccess.Result result;
                try {
                    result = RootAccess.execute(observationCommand(), 20000L, ROOT_OUTPUT_LIMIT);
                } catch (RuntimeException failure) {
                    result = RootAccess.failure(126,
                            "读取 OBSERVE 日志异常：" + failure.getClass().getSimpleName());
                }
                final RootAccess.Result completed = result;
                runOnUiThread(() -> {
                    refreshInFlight.set(false);
                    if (refreshButton != null) refreshButton.setEnabled(true);
                    if (destroyed || isFinishing() || isDestroyed()
                            || request != generation) return;
                    if (completed == null) {
                        rawOutput = "";
                        status.setText("读取 OBSERVE 日志失败：Root 没有返回结果。");
                        render();
                        return;
                    }
                    String output = completed.output == null ? "" : completed.output.trim();
                    if (output.contains("FX_HOOK_MODULE_UNAVAILABLE")) {
                        rawOutput = "";
                        status.setText("未找到可用的 privacyguard KernelSU 模块，无法读取 Hook 日志。");
                    } else if (output.contains("LOGCAT_UNAVAILABLE")) {
                        rawOutput = "";
                        status.setText("当前系统没有可用的 logcat 命令。");
                    } else if (completed.exitCode != 0) {
                        rawOutput = "";
                        String detail = output.length() > 180 ? output.substring(0, 180) : output;
                        status.setText("读取 OBSERVE 日志失败（退出码 " + completed.exitCode
                                + (completed.denied ? "，Root 权限被拒绝" : "")
                                + (detail.isEmpty() ? "）。" : "）：" + detail));
                    } else {
                        rawOutput = output;
                        int records = countLines(output);
                        status.setText(records == 0
                                ? "没有找到此目标的 OBSERVE 记录。请确认配置已发布、目标为 debuggable 构建，并已触发被观察的方法。"
                                : "读取完成 · " + records + " 条记录（最多显示最近 300 条）。");
                    }
                    render();
                });
            });
        } catch (RejectedExecutionException full) {
            refreshInFlight.set(false);
            if (refreshButton != null) refreshButton.setEnabled(true);
            status.setText("读取队列繁忙，本次刷新未执行，请稍后重试。");
        }
    }

    private int countLines(String value) {
        if (value == null || value.isEmpty()) return 0;
        int count = 1;
        for (int i = 0; i < value.length(); i++) if (value.charAt(i) == '\n') count++;
        return count;
    }

    private void render() {
        if (outputView == null || search == null || count == null) return;
        final int previousScrollY = restoreScrollPending ? restoredScrollY
                : (logScroll == null ? 0 : logScroll.getScrollY());
        restoreScrollPending = false;
        if (rawOutput.isEmpty()) {
            outputView.setText("暂无可显示的 OBSERVE 记录。");
            count.setText("匹配记录：0");
            if (logScroll != null) logScroll.post(() -> logScroll.scrollTo(0, previousScrollY));
            return;
        }
        String needle = search.getText() == null ? ""
                : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        StringBuilder result = new StringBuilder();
        int matched = 0;
        for (String line : rawOutput.split("\\r?\\n")) {
            if (!needle.isEmpty() && !line.toLowerCase(Locale.ROOT).contains(needle)) continue;
            if (matched > 0) result.append('\n');
            result.append(line);
            matched++;
        }
        String visible = result.toString();
        boolean truncated = visible.length() > DISPLAY_LIMIT;
        if (truncated) visible = visible.substring(0, DISPLAY_LIMIT) + "\n…（显示内容已截断）";
        count.setText("匹配记录：" + matched + (truncated ? " · 显示已截断" : ""));
        outputView.setText(matched == 0 ? "没有符合条件的 OBSERVE 记录。" : visible);
        if (logScroll != null) logScroll.post(() -> logScroll.scrollTo(0, previousScrollY));
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putString("fx_hook_observe_search",
                search == null || search.getText() == null ? "" : search.getText().toString());
        outState.putInt("fx_hook_observe_scroll_y", logScroll == null ? 0 : logScroll.getScrollY());
        super.onSaveInstanceState(outState);
    }

    @Override protected void onDestroy() {
        destroyed = true;
        generation++;
        refreshInFlight.set(false);
        worker.shutdownNow();
        super.onDestroy();
    }
}
