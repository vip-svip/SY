package de.privacyguard.adhook.imported.dia;

import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.RootAccess;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

/**
 * Native Dia monitor-event page. It reads only the FX-owned session log and
 * displays the allowlisted metadata produced by FxDiaMonitorEventParser.
 */
public final class FxDiaMonitorEventsActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    public static final String EXTRA_TARGET_PACKAGE = "fx_dia_monitor_target_package";
    public static final String EXTRA_TARGET_NAME = "fx_dia_monitor_target_name";
    private static final int MAX_ROOT_OUTPUT = 512 * 1024;
    private static final long REFRESH_INTERVAL_MS = 15000L;
    private static final int MAX_RESTORED_SEARCH_CHARS = 256;
    private static final String STATE_SEARCH = "fx_dia_monitor_state_search";
    private static final String STATE_CATEGORY = "fx_dia_monitor_state_category";
    private static final String STATE_AUTO_REFRESH = "fx_dia_monitor_state_auto_refresh";
    private static final String STATE_SCROLL_Y = "fx_dia_monitor_state_scroll_y";

    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "fx-dia-monitor-events");
        thread.setDaemon(true);
        return thread;
    });
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable autoRefresh = new Runnable() {
        @Override public void run() {
            if (isFinishing() || isDestroyed() || !autoRefreshSwitch.isChecked()) return;
            loadEvents(false);
            main.postDelayed(this, REFRESH_INTERVAL_MS);
        }
    };

    private String targetPackage;
    private String targetName;
    private String logPath;
    private int loadGeneration;
    private boolean destroyed;
    private List<FxDiaMonitorEventParser.Event> events = new ArrayList<>();

    private TextView status;
    private TextView count;
    private Spinner category;
    private EditText search;
    private Switch autoRefreshSwitch;
    private LinearLayout rows;
    private ScrollView logScroll;
    private boolean restoringUiState;
    private boolean eventsLoaded;
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
        if (!isSafePackageName(targetPackage)) {
            Toast.makeText(this, "监控目标包名无效，无法读取事件。", Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        if (targetName == null || targetName.trim().isEmpty()) targetName = targetPackage;
        logPath = "/data/adb/privacyguard/dia-frida/logs/" + targetPackage + ".log";
        buildPage();
        restoreUiState(state);
        loadEvents(true);
    }

    private static boolean isSafePackageName(String value) {
        return value != null && value.length() <= 255
                && value.matches("[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+")
                && !value.contains("..");
    }

    private String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private void buildPage() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(8), dp(4), dp(12), dp(4));
        header.addView(button("‹ 返回 Hook", this::finish));
        TextView title = text("Hook · 结构化监控事件", 18, 0xff17212b, true);
        title.setTag("fx-title:18");
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        TextView target = text("目标应用：" + targetName + "\n包名：" + targetPackage,
                12, 0xff526170, false);
        target.setTag("fx-card-detail");
        target.setPadding(dp(16), dp(3), dp(16), dp(7));
        root.addView(target);

        status = text("正在读取 FX 监控事件…", 12, 0xff526170, false);
        status.setTag("fx-card-detail");
        status.setPadding(dp(16), dp(5), dp(16), dp(5));
        root.addView(status);

        LinearLayout controls = new LinearLayout(this);
        controls.setTag("fx-card-group");
        controls.setOrientation(LinearLayout.VERTICAL);
        controls.setPadding(dp(12), dp(4), dp(12), dp(4));
        controls.setBackgroundColor(0xfff0f3f7);

        TextView privacy = text(
                "只显示 FX 内置 [DIA_*] 监控模板产生的白名单元数据；不会显示 SQL 文本、网络正文/请求头、命令内容、调用栈或自定义脚本原文。",
                12, 0xff617080, false);
        privacy.setTag("fx-card-detail");
        controls.addView(privacy);

        String[] categories = FxDiaMonitorEventParser.getCategories();
        String[] options = new String[categories.length + 1];
        options[0] = "全部类型";
        System.arraycopy(categories, 0, options, 1, categories.length);
        category = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(
                this, android.R.layout.simple_spinner_item, options);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        category.setAdapter(adapter);
        controls.addView(category);

        search = new EditText(this);
        search.setSingleLine(true);
        search.setHint("搜索主机、类名、方法或状态码");
        controls.addView(search);

        LinearLayout actions = new LinearLayout(this);
        actions.setTag("fx-card-group");
        actions.setGravity(Gravity.CENTER_VERTICAL);
        Button refresh = button("立即刷新", () -> loadEvents(true));
        actions.addView(refresh, new LinearLayout.LayoutParams(0, -2, 1));
        autoRefreshSwitch = new Switch(this);
        autoRefreshSwitch.setTag("fx-switch-row");
        autoRefreshSwitch.setText("每 15 秒自动刷新");
        autoRefreshSwitch.setTextSize(12);
        autoRefreshSwitch.setOnCheckedChangeListener((button, checked) -> {
            if (restoringUiState) return;
            main.removeCallbacks(autoRefresh);
            if (checked) {
                loadEvents(true);
                main.postDelayed(autoRefresh, REFRESH_INTERVAL_MS);
            }
        });
        actions.addView(autoRefreshSwitch);
        controls.addView(actions);
        root.addView(controls);

        count = text("匹配事件：0", 12, 0xff617080, false);
        count.setTag("fx-card-detail");
        count.setPadding(dp(16), dp(5), dp(16), dp(5));
        root.addView(count);

        logScroll = new ScrollView(this);
        logScroll.setFillViewport(true);
        rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        rows.setPadding(dp(8), dp(3), dp(8), dp(12));
        logScroll.addView(rows);
        root.addView(logScroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 4);

        category.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view,
                                                 int position, long id) {
                renderEvents();
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        search.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count,
                                                    int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before,
                                                int count) {
                renderEvents();
            }
            @Override public void afterTextChanged(Editable editable) { }
        });
    }

    private void loadEvents(boolean showLoading) {
        if (destroyed || logPath == null) return;
        final int request = ++loadGeneration;
        if (showLoading) status.setText("正在读取最近的结构化监控事件…");
        final String command = "if [ -f " + shellQuote(logPath) + " ] && [ ! -L "
                + shellQuote(logPath) + " ] && [ -r " + shellQuote(logPath)
                + " ] && [ -s " + shellQuote(logPath) + " ]; then tail -n 800 "
                + shellQuote(logPath) + "; else echo FX_DIA_NO_EVENTS; fi";
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(command, 15000L, MAX_ROOT_OUTPUT);
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()
                            || request != loadGeneration) return;
                    if (result == null || result.exitCode != 0) {
                        String detail = result == null || result.output == null
                                ? "Root 读取失败。" : result.output.trim();
                        if (detail.length() > 240) detail = detail.substring(0, 240);
                        status.setText("读取监控事件失败："
                                + (detail.isEmpty() ? "没有错误详情。" : detail));
                        events = new ArrayList<>();
                        eventsLoaded = true;
                        renderEvents();
                        return;
                    }
                    String output = result.output == null ? "" : result.output;
                    events = FxDiaMonitorEventParser.parse(output);
                    eventsLoaded = true;
                    String updated = new SimpleDateFormat("HH:mm:ss", Locale.ROOT)
                            .format(new Date());
                    status.setText("最近读取：" + updated + " · 事件读取成功；仅展示安全字段。");
                    renderEvents();
                });
            });
        } catch (RejectedExecutionException full) {
            status.setText("读取队列繁忙，本次刷新未执行；请稍后重试。");
            eventsLoaded = true;
            renderEvents();
        }
    }

    private void renderEvents() {
        if (rows == null || category == null || search == null || count == null) return;
        rows.removeAllViews();
        String[] categories = FxDiaMonitorEventParser.getCategories();
        int selectedPosition = category.getSelectedItemPosition();
        String selected = selectedPosition <= 0 || selectedPosition > categories.length
                ? "" : categories[selectedPosition - 1];
        String needle = search.getText() == null ? ""
                : search.getText().toString().trim().toLowerCase(Locale.ROOT);
        int matched = 0;
        int shown = 0;
        for (FxDiaMonitorEventParser.Event event : events) {
            if (!selected.isEmpty() && !selected.equals(event.category)) continue;
            String display = event.toDisplayString();
            if (!needle.isEmpty() && !display.toLowerCase(Locale.ROOT).contains(needle)) continue;
            matched++;
            if (shown >= 120) continue;
            LinearLayout row = new LinearLayout(this);
            row.setTag("fx-list-row");
            row.setOrientation(LinearLayout.VERTICAL);
            TextView eventText = text(display, 12, 0xff263443, false);
            eventText.setTag("fx-list-subtitle");
            eventText.setPadding(dp(12), dp(8), dp(12), dp(8));
            row.addView(eventText);
            row.setOnClickListener(v -> {
                AlertDialog dialog = new AlertDialog.Builder(this)
                        .setTitle("监控事件 · " + event.category)
                        .setMessage(event.toDisplayString())
                        .setPositiveButton("关闭", null)
                        .create();
                FxNativeSkin.showDialog(this, dialog);
            });
            rows.addView(row, new LinearLayout.LayoutParams(-1, -2));
            shown++;
        }
        count.setText("匹配事件：" + matched + " · 当前显示：" + shown
                + (matched > shown ? "（列表最多显示 120 条，请缩小筛选范围）" : ""));
        if (matched == 0) {
            TextView empty = text(events.isEmpty()
                            ? "当前目标没有可显示的内置监控事件。先在 Dia Frida 页面选择目标并注入相应监控模板，再返回刷新。"
                            : "没有符合条件的事件，请调整类型或搜索词。",
                    13, 0xff617080, false);
            empty.setPadding(dp(16), dp(18), dp(16), dp(18));
            rows.addView(empty);
        }
        restorePendingScrollPosition();
    }

    private void restoreUiState(Bundle state) {
        if (state == null) return;
        restoringUiState = true;
        String query = state.getString(STATE_SEARCH, "");
        if (query == null) query = "";
        if (query.length() > MAX_RESTORED_SEARCH_CHARS) {
            query = query.substring(0, MAX_RESTORED_SEARCH_CHARS);
        }
        search.setText(query);
        search.setSelection(search.getText().length());
        int savedCategory = state.getInt(STATE_CATEGORY, 0);
        if (savedCategory >= 0 && savedCategory < category.getCount()) {
            category.setSelection(savedCategory);
        }
        autoRefreshSwitch.setChecked(state.getBoolean(STATE_AUTO_REFRESH, false));
        restoredScrollY = Math.max(0, state.getInt(STATE_SCROLL_Y, 0));
        pendingScrollRestore = true;
        restoringUiState = false;
    }

    private void restorePendingScrollPosition() {
        if (!eventsLoaded || !pendingScrollRestore || logScroll == null) return;
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
        if (category != null) outState.putInt(STATE_CATEGORY, category.getSelectedItemPosition());
        if (autoRefreshSwitch != null) {
            outState.putBoolean(STATE_AUTO_REFRESH, autoRefreshSwitch.isChecked());
        }
        if (logScroll != null) outState.putInt(STATE_SCROLL_Y, Math.max(0, logScroll.getScrollY()));
    }

    @Override protected void onResume() {
        super.onResume();
        if (autoRefreshSwitch != null && autoRefreshSwitch.isChecked()) {
            main.removeCallbacks(autoRefresh);
            main.postDelayed(autoRefresh, REFRESH_INTERVAL_MS);
        }
    }

    @Override protected void onPause() {
        main.removeCallbacks(autoRefresh);
        super.onPause();
    }

    @Override protected void onDestroy() {
        destroyed = true;
        loadGeneration++;
        main.removeCallbacksAndMessages(null);
        worker.shutdownNow();
        super.onDestroy();
    }
}
