package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import de.privacyguard.adhook.RootAccess;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Yulong 7.0.1 app whitelist: excludes selected UIDs from FX ad/DNS filtering. */
public final class FxYulongAppWhitelistActivity extends Activity {
    private static final int APP_PAGE_SIZE = 50;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> new Thread(r, "fx-yulong-whitelist-root"), new ThreadPoolExecutor.AbortPolicy());
    private final ThreadPoolExecutor appWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-yulong-whitelist-apps"), new ThreadPoolExecutor.AbortPolicy());
    private int appPage = 1;
    private volatile boolean destroyed;
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final Map<String, String> labels = new HashMap<>();
    private final Map<String, Boolean> selected = new HashMap<>();
    private LinearLayout list;
    private TextView status;
    private EditText query;
    private boolean loading = true;
    private boolean appLoading;

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }
    private String quote(String value) {
        return "'" + (value == null ? "" : value.replace("'", "'\\''")) + "'";
    }
    private String command(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; "
                + "then MP=\\"$d\\"; break; fi; done; "
                + "[ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-app-whitelist.sh\\" " + args;
    }
    private void root(String args, java.util.function.Consumer<RootAccess.Result> callback) {
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(command(args), 90000L, 512 * 1024);
                runOnUiThread(() -> {
                    if (!destroyed && !isFinishing() && !isDestroyed()) callback.accept(result);
                });
            });
        } catch (RejectedExecutionException full) {
            runOnUiThread(() -> {
                if (!destroyed && !isFinishing() && !isDestroyed()) {
                    status.setText("Root 操作队列已满，请稍后重试。");
                    callback.accept(RootAccess.execute(""));
                }
            });
        }
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
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

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("游龙广告插件 · 应用白名单", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);

        TextView intro = text(
                "加入白名单的应用会绕过 FX 广告/DNS 过滤通道。FX TUN 模式通过 sing-box exclude_uid 排除应用；第三方 VPN 兼容模式通过 FX Root DNS Proxy 的 UID 放行规则排除应用。此名单独立于分应用代理名单和网络阻断名单。",
                13, 0xff617080, false);
        body.addView(intro);
        status = text("正在读取设备端白名单…", 12, 0xff526170, false);
        body.addView(status);
        query = new EditText(this);
        query.setSingleLine(true);
        query.setHint("搜索应用名称或包名");
        body.addView(query);
        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        body.addView(list);

        query.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) { }
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                appPage = 1;
                renderRows();
            }
            @Override public void afterTextChanged(Editable s) { }
        });

        root("list", result -> {
            if (result.exitCode != 0) {
                loading = false;
                status.setText("无法读取白名单：" + safe(result.output));
                return;
            }
            parse(result.output);
            loading = false;
            loadAppsAsync();
        });
    }

    private String safe(String output) {
        return output == null || output.trim().isEmpty()
                ? "请确认 FX Hook 已获得 Root 权限。" : output.trim();
    }
    private void parse(String output) {
        selected.clear();
        for (String line : (output == null ? "" : output).split("\\r?\\n")) {
            if (line.startsWith("FXYULONGWHITE1")) continue;
            String[] parts = line.split("\\|", -1);
            if (parts.length == 3 && parts[0].contains(".")
                    && ("0".equals(parts[2]) || "1".equals(parts[2]))) {
                selected.put(parts[0], "1".equals(parts[2]));
            }
        }
    }
    /** Package enumeration, label resolution and sorting stay off the Activity UI thread. */
    private void loadAppsAsync() {
        appLoading = true;
        status.setText("正在后台读取已安装应用…");
        renderRows();
        try {
            appWorker.execute(() -> {
                List<ApplicationInfo> loaded = new ArrayList<>();
                Map<String, String> loadedLabels = new HashMap<>();
                Throwable failure = null;
                try {
                    PackageManager pm = getApplicationContext().getPackageManager();
                    loaded.addAll(pm.getInstalledApplications(0));
                    loaded.removeIf(info -> info.packageName == null
                            || info.packageName.equals(getPackageName()));
                    for (ApplicationInfo info : loaded) {
                        String label;
                        try { label = String.valueOf(pm.getApplicationLabel(info)); }
                        catch (Throwable ignored) { label = info.packageName; }
                        loadedLabels.put(info.packageName, label);
                    }
                    loaded.sort(Comparator.comparing(info ->
                            loadedLabels.getOrDefault(info.packageName, info.packageName)
                                    .toLowerCase(Locale.ROOT)));
                } catch (Throwable error) {
                    failure = error;
                }
                final Throwable loadFailure = failure;
                runOnUiThread(() -> {
                    if (destroyed || isFinishing() || isDestroyed()) return;
                    appLoading = false;
                    if (loadFailure != null) {
                        status.setText("无法读取应用列表：" + loadFailure.getClass().getSimpleName());
                        renderRows();
                        return;
                    }
                    apps.clear();
                    apps.addAll(loaded);
                    labels.clear();
                    labels.putAll(loadedLabels);
                    for (ApplicationInfo info : loaded) {
                        selected.putIfAbsent(info.packageName, false);
                    }
                    appPage = 1;
                    updateStatus();
                    renderRows();
                });
            });
        } catch (RejectedExecutionException closing) {
            appLoading = false;
            if (!destroyed && !isFinishing()) status.setText("应用列表加载任务已停止，请重新打开页面。");
        }
    }
    private void updateStatus() {
        if (loading) {
            status.setText("正在读取设备端白名单…");
            return;
        }
        if (appLoading) {
            status.setText("正在后台读取已安装应用…");
            return;
        }
        int enabled = 0;
        for (Boolean value : selected.values()) if (Boolean.TRUE.equals(value)) enabled++;
        status.setText("已排除 " + enabled + " 个应用。每次修改都会保存配置并重新应用网络规则。");
    }
    private void renderRows() {
        if (list == null || isFinishing() || destroyed) return;
        list.removeAllViews();
        if (loading || appLoading) {
            list.addView(text("正在读取白名单和应用信息…", 13, 0xff617080, false));
            return;
        }
        String filter = query.getText() == null ? ""
                : query.getText().toString().trim().toLowerCase(Locale.ROOT);
        int matched = 0;
        int shown = 0;
        int limit = Math.max(1, appPage) * APP_PAGE_SIZE;
        for (ApplicationInfo app : apps) {
            String pkg = app.packageName;
            String label = labels.getOrDefault(pkg, pkg);
            if (!filter.isEmpty() && !pkg.toLowerCase(Locale.ROOT).contains(filter)
                    && !label.toLowerCase(Locale.ROOT).contains(filter)) continue;
            matched++;
            if (shown >= limit) continue;

            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setPadding(dp(12), dp(6), dp(12), dp(6));
            item.setBackgroundColor(0xffffffff);
            item.addView(text(label, 14, 0xff17212b, true));
            item.addView(text(pkg + " · UID " + app.uid, 10, 0xff718091, false));

            Switch enabled = new Switch(this);
            enabled.setText("排除广告/DNS 过滤");
            enabled.setChecked(Boolean.TRUE.equals(selected.get(pkg)));
            final boolean[] suppress = {false};
            enabled.setOnCheckedChangeListener((button, checked) -> {
                if (suppress[0]) return;
                button.setEnabled(false);
                root((checked ? "add " : "remove ") + quote(pkg), result -> {
                    button.setEnabled(true);
                    if (result.exitCode != 0) {
                        suppress[0] = true;
                        button.setChecked(!checked);
                        suppress[0] = false;
                        status.setText("白名单更新失败：" + safe(result.output));
                    } else {
                        selected.put(pkg, checked);
                        updateStatus();
                    }
                });
            });
            item.addView(enabled);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(12), dp(2), dp(12), dp(2));
            list.addView(item, lp);
            shown++;
        }
        if (shown == 0) list.addView(text("没有匹配的应用。", 13, 0xff617080, false));
        if (matched > limit) {
            list.addView(button("加载更多（剩余 " + (matched - limit) + " 个）", () -> {
                appPage++;
                renderRows();
            }), new LinearLayout.LayoutParams(-1, -2));
        }
    }
    @Override protected void onDestroy() {
        destroyed = true;
        worker.shutdownNow();
        appWorker.shutdownNow();
        super.onDestroy();
    }
}
