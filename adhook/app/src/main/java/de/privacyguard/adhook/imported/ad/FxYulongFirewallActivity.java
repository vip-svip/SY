package de.privacyguard.adhook.imported.ad;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.net.TrafficStats;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
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

/** Native Yulong 7.0.1 per-app firewall UI; separate from FX's per-app VPN route. */
public final class FxYulongFirewallActivity extends Activity {
    private static final int APP_PAGE_SIZE = 50;
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(8),
            r -> new Thread(r, "fx-yulong-firewall-root"), new ThreadPoolExecutor.AbortPolicy());
    private final ThreadPoolExecutor appWorker = new ThreadPoolExecutor(1, 1, 30L,
            TimeUnit.SECONDS, new ArrayBlockingQueue<>(1),
            r -> new Thread(r, "fx-yulong-firewall-apps"), new ThreadPoolExecutor.AbortPolicy());
    private int appPage = 1;
    private volatile boolean destroyed;
    private LinearLayout rows;
    private TextView status;
    private Switch master;
    private EditText query;
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final Map<String, String> labels = new HashMap<>();
    private final Map<String, Boolean> selected = new HashMap<>();
    private boolean loading = true;
    private boolean suppressMaster;
    private String suitePage = "应用网络拦截";
    private int appFilterMode;

    private int dp(float n) {
        return (int)(n * getResources().getDisplayMetrics().density + 0.5f);
    }
    private String scriptCommand(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard "
                + "/data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; sh \"$MP/scripts/yulong-app-firewall.sh\" " + args;
    }
    private String quote(String s) {
        return "'" + (s == null ? "" : s.replace("'", "'\\''")) + "'";
    }
    private void runRoot(String args, java.util.function.Consumer<RootAccess.Result> callback) {
        try {
            worker.execute(() -> {
                RootAccess.Result result = RootAccess.execute(scriptCommand(args), 60000L, 1024 * 1024);
                runOnUiThread(() -> {
                    if (!destroyed && !isFinishing() && !isDestroyed()) callback.accept(result);
                });
            });
        } catch (RejectedExecutionException full) {
            // Queue saturation is a completed operation failure, not a fake
            // command-validation attempt. Do not call the Root process at all.
            RootAccess.Result rejected = RootAccess.failure(
                    75, "后台任务繁忙，本次防火墙操作未执行。");
            runOnUiThread(() -> {
                if (!destroyed && !isFinishing() && !isDestroyed()) {
                    status.setText("后台任务繁忙，本次防火墙操作未执行。");
                    callback.accept(rejected);
                }
            });
        }
    }
    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value); view.setTextSize(size); view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5)); return view;
    }
    private Button button(String value, Runnable action) {
        Button b = new Button(this); b.setAllCaps(false); b.setText(value);
        b.setOnClickListener(v -> action.run()); return b;
    }
    private void card(String title, String detail, View... children) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL); card.setPadding(dp(14), dp(10), dp(14), dp(10));
        card.setBackgroundColor(0xfff0f3f7);
        card.addView(text(title, 16, 0xff17212b, true));
        card.addView(text(detail, 12, 0xff617080, false));
        if (children != null) {
            for (View child : children) if (child != null) card.addView(child);
        }
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(12), dp(5), dp(12), dp(5)); rows.addView(card, lp);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        String requestedPage = getIntent() == null ? null : getIntent().getStringExtra("suite_page");
        if ("用户应用".equals(requestedPage) || "系统应用".equals(requestedPage)
                || "按应用设置".equals(requestedPage) || "应用网络拦截".equals(requestedPage)) {
            suitePage = requestedPage;
        } else {
            suitePage = "应用网络拦截";
        }
        appFilterMode = "用户应用".equals(suitePage) ? 1 : "系统应用".equals(suitePage) ? 2 : 0;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(0xfff7f8fa);
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL); header.setPadding(dp(10), dp(6), dp(12), dp(6));
        header.addView(button("‹ 返回", this::finish));
        header.addView(text("游龙广告插件 · " + suitePage, 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);
        ScrollView scroll = new ScrollView(this); scroll.setFillViewport(true);
        rows = new LinearLayout(this); rows.setOrientation(LinearLayout.VERTICAL);
        rows.setPadding(0, dp(4), 0, dp(20)); scroll.addView(rows);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1)); setContentView(root);

        TextView intro = text("按应用 UID 在系统 OUTPUT 链同时阻断 IPv4/IPv6 外连。它独立于 FX 分应用 VPN 路由，不启动第二个 VpnService；默认关闭，只有手动选择应用并启用后才生效。", 13, 0xff617080, false);
        card("防火墙说明", "系统级应用网络限制", intro);
        status = text("正在读取设备端防火墙设置…", 13, 0xff526170, false);
        card("当前状态", "Root 与 IPv4/IPv6 规则应用结果", status);
        master = new Switch(this); master.setText("启用已选择应用的网络拦截");
        master.setEnabled(false);
        card("防火墙总开关", "关闭时只移除 FX 自己的防火墙链，不修改其他应用的规则。", master);
        query = new EditText(this); query.setSingleLine(true); query.setHint("搜索应用名称或包名");
        query.setPadding(dp(14), dp(8), dp(14), dp(8));
        card("应用列表", "选择要完全阻断网络的应用；每个 UID 的收发计数由 Android TrafficStats 提供，按刷新时刻读取。", query, button("刷新流量统计", this::renderRows));
        master.setOnCheckedChangeListener((button, checked) -> {
            if (loading || suppressMaster) return;
            if (checked && !selected.containsValue(Boolean.TRUE)) {
                suppressMaster = true; master.setChecked(false); suppressMaster = false;
                status.setText("启用前至少选择一个应用。"); return;
            }
            master.setEnabled(false);
            runRoot("master " + (checked ? "1" : "0"), result -> {
                master.setEnabled(true);
                if (result.exitCode != 0) {
                    suppressMaster = true; master.setChecked(!checked); suppressMaster = false;
                    status.setText("防火墙未应用：" + safeOutput(result.output));
                } else status.setText(checked ? "应用网络拦截已启用。" : "应用网络拦截已关闭。");
            });
        });
        query.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
            @Override public void onTextChanged(CharSequence s, int start, int before, int count) {
                appPage = 1;
                renderRows();
            }
            @Override public void afterTextChanged(Editable s) {}
        });
        runRoot("list", result -> {
            if (result.exitCode != 0) {
                loading = false; master.setEnabled(false);
                status.setText("无法读取防火墙配置：" + safeOutput(result.output)); return;
            }
            parseList(result.output);
            loadAppsAsync();
        });
    }
    private String safeOutput(String value) {
        return value == null || value.trim().isEmpty() ? "请确认 FX Hook 已获得 Root 权限。" : value.trim();
    }
    private void parseList(String output) {
        selected.clear();
        for (String line : (output == null ? "" : output).split("\\r?\\n")) {
            if (line.startsWith("master=")) {
                suppressMaster = true; master.setChecked("1".equals(line.substring(7).trim())); suppressMaster = false;
            } else if (line.startsWith("FXYULONGFW1")) {
                // header
            } else {
                String[] p = line.split("\\|", -1);
                if (p.length == 3 && p[0].contains(".") && ("0".equals(p[2]) || "1".equals(p[2])))
                    selected.put(p[0], "1".equals(p[2]));
            }
        }
    }
    /** Package enumeration, label resolution and sorting must never block the Activity UI. */
    private void loadAppsAsync() {
        loading = true;
        master.setEnabled(false);
        status.setText("正在后台读取已安装应用…");
        try {
            appWorker.execute(() -> {
                List<ApplicationInfo> loaded = new ArrayList<>();
                Map<String, String> loadedLabels = new HashMap<>();
                Throwable failure = null;
                try {
                    PackageManager pm = getPackageManager();
                    loaded.addAll(pm.getInstalledApplications(0));
                    loaded.removeIf(info -> {
                        if (info.packageName == null || info.packageName.equals(getPackageName())) return true;
                        boolean systemApp = (info.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                                || (info.flags & ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0;
                        return appFilterMode == 1 ? systemApp : appFilterMode == 2 && !systemApp;
                    });
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
                    if (loadFailure != null) {
                        loading = false;
                        master.setEnabled(false);
                        status.setText("无法读取应用列表：" + loadFailure.getClass().getSimpleName());
                        renderRows();
                        return;
                    }
                    apps.clear();
                    apps.addAll(loaded);
                    labels.clear();
                    labels.putAll(loadedLabels);
                    for (ApplicationInfo info : loaded) {
                        if (!selected.containsKey(info.packageName)) selected.put(info.packageName, false);
                    }
                    loading = false;
                    master.setEnabled(true);
                    status.setText("已读取 " + apps.size() + " 个" + ("用户应用".equals(suitePage) ? "用户应用" : "系统应用".equals(suitePage) ? "系统应用" : "应用") + "；列表按需分页加载。");
                    appPage = 1;
                    renderRows();
                });
            });
        } catch (java.util.concurrent.RejectedExecutionException closing) {
            loading = false;
            if (!destroyed && !isFinishing()) status.setText("应用列表加载任务已停止，请重新打开页面。");
        }
    }
    private String formatBytes(long bytes) {
        if (bytes < 0) return "系统未提供";
        if (bytes < 1024) return bytes + " B";
        double value = bytes;
        String[] units = {"B", "KiB", "MiB", "GiB", "TiB"};
        int unit = 0;
        while (value >= 1024.0 && unit < units.length - 1) {
            value /= 1024.0;
            unit++;
        }
        return String.format(Locale.ROOT, "%.2f %s", value, units[unit]);
    }

    private void renderRows() {
        if (rows == null || isFinishing() || destroyed) return;
        // The first four children are the fixed intro/status/master/app-list cards.
        rows.removeViews(4, Math.max(0, rows.getChildCount() - 4));
        String filter = query.getText() == null ? "" : query.getText().toString().trim().toLowerCase(Locale.ROOT);
        int matched = 0;
        int shown = 0;
        int limit = Math.max(1, appPage) * APP_PAGE_SIZE;
        for (ApplicationInfo info : apps) {
            String pkg = info.packageName; String label = labels.getOrDefault(pkg, pkg);
            if (!filter.isEmpty() && !label.toLowerCase(Locale.ROOT).contains(filter)
                    && !pkg.toLowerCase(Locale.ROOT).contains(filter)) continue;
            matched++;
            if (shown >= limit) continue;
            LinearLayout item = new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL);
            item.setPadding(dp(12), dp(7), dp(12), dp(7));
            TextView name = text(label, 14, 0xff17212b, true);
            TextView packageText = text(pkg + " · UID " + info.uid, 10, 0xff718091, false);
            long received = TrafficStats.getUidRxBytes(info.uid);
            long transmitted = TrafficStats.getUidTxBytes(info.uid);
            TextView traffic = text("本次系统 UID 计数 · 接收 " + formatBytes(received)
                    + " · 发送 " + formatBytes(transmitted), 10, 0xff526170, false);
            Switch blocked = new Switch(this); blocked.setText("阻断该应用的全部网络");
            blocked.setChecked(Boolean.TRUE.equals(selected.get(pkg)));
            final boolean[] suppressRow = {false};
            blocked.setOnCheckedChangeListener((button, enabled) -> {
                if (suppressRow[0]) return;
                button.setEnabled(false);
                runRoot("set " + quote(pkg) + " " + info.uid + " " + (enabled ? "1" : "0"), result -> {
                    button.setEnabled(true);
                    if (result.exitCode != 0) {
                        suppressRow[0] = true;
                        button.setChecked(!enabled);
                        suppressRow[0] = false;
                        status.setText("应用防火墙更新失败：" + safeOutput(result.output));
                    } else {
                        selected.put(pkg, enabled);
                        status.setText(enabled ? "已加入网络拦截名单。" : "已从网络拦截名单移除。");
                    }
                });
            });
            item.addView(name); item.addView(packageText); item.addView(traffic); item.addView(blocked);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
            lp.setMargins(dp(12), dp(2), dp(12), dp(2)); rows.addView(item, lp); shown++;
        }
        if (shown == 0) rows.addView(text("没有匹配的应用。", 13, 0xff617080, false));
        if (matched > limit) {
            rows.addView(button("加载更多（剩余 " + (matched - limit) + " 个）", () -> {
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
